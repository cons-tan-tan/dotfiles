use crate::model::{BatterySource, BatteryState};
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::process::CommandExt as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use std::time::{SystemTime, UNIX_EPOCH};

const PMSET: &str = "/usr/bin/pmset";
const IOREG: &str = "/usr/sbin/ioreg";
const SENTINEL_NAME: &str = "active.json";
const COMMAND_TIMEOUT: Duration = Duration::from_secs(3);
const MAX_COMMAND_OUTPUT: usize = 64 * 1024;

pub trait CommandRunner: Send + Sync {
    fn output(&self, program: &str, args: &[&str]) -> io::Result<Output>;
}

#[derive(Default)]
pub struct SystemCommandRunner;

impl CommandRunner for SystemCommandRunner {
    fn output(&self, program: &str, args: &[&str]) -> io::Result<Output> {
        command_output_with_timeout(program, args, COMMAND_TIMEOUT)
    }
}

fn command_output_with_timeout(
    program: &str,
    args: &[&str],
    timeout: Duration,
) -> io::Result<Output> {
    let mut child = Command::new(program)
        .args(args)
        .process_group(0)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("failed to capture command stdout"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| io::Error::other("failed to capture command stderr"))?;
    let stdout_reader = thread::spawn(move || read_bounded(stdout));
    let stderr_reader = thread::spawn(move || read_bounded(stderr));
    let deadline = Instant::now() + timeout;
    let status = loop {
        let status = child.try_wait()?;
        if let Some(status) = status
            && stdout_reader.is_finished()
            && stderr_reader.is_finished()
        {
            break status;
        }
        if Instant::now() >= deadline {
            let process_group = i32::try_from(child.id()).ok();
            if let Some(process_group) = process_group {
                // SAFETY: the child was created as its own process-group
                // leader; a negative PID targets only it and descendants that
                // inherited its group.
                let _ = unsafe { libc::kill(-process_group, libc::SIGKILL) };
            } else {
                let _ = child.kill();
            }
            let _ = child.wait();
            if stdout_reader.is_finished() {
                let _ = stdout_reader.join();
            }
            if stderr_reader.is_finished() {
                let _ = stderr_reader.join();
            }
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("{program} exceeded its {timeout:?} deadline"),
            ));
        }
        thread::sleep(Duration::from_millis(10));
    };
    let stdout = stdout_reader
        .join()
        .map_err(|_| io::Error::other("stdout reader thread panicked"))??;
    let stderr = stderr_reader
        .join()
        .map_err(|_| io::Error::other("stderr reader thread panicked"))??;
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

fn read_bounded(mut reader: impl Read) -> io::Result<Vec<u8>> {
    let mut retained = Vec::new();
    let mut buffer = [0_u8; 8 * 1024];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            return Ok(retained);
        }
        let available = MAX_COMMAND_OUTPUT.saturating_sub(retained.len());
        retained.extend_from_slice(&buffer[..read.min(available)]);
    }
}

pub trait PowerController: Send + Sync {
    fn ensure_state_directory(&self) -> io::Result<()>;
    fn fixed_commands_available(&self) -> io::Result<bool>;
    fn sleep_disabled(&self) -> io::Result<bool>;
    fn set_sleep_disabled(&self, disabled: bool) -> io::Result<()>;
    fn battery_state(&self) -> io::Result<BatteryState>;
    fn lid_closed(&self) -> io::Result<bool>;
    fn sleep_now(&self) -> io::Result<()>;
    fn sentinel_exists(&self) -> io::Result<bool>;
    fn write_sentinel(&self, instance_id: &str) -> io::Result<()>;
    fn remove_sentinel(&self) -> io::Result<()>;
    fn state_directory_secure(&self) -> io::Result<bool>;
}

pub struct SystemPowerController<R = SystemCommandRunner> {
    runner: R,
    state_dir: PathBuf,
    owner_uid: u32,
}

impl Default for SystemPowerController {
    fn default() -> Self {
        Self {
            runner: SystemCommandRunner,
            state_dir: PathBuf::from("/var/db/sleepctl"),
            owner_uid: 0,
        }
    }
}

impl<R> SystemPowerController<R> {
    #[cfg(test)]
    fn with_runner(runner: R, state_dir: PathBuf) -> Self {
        Self {
            runner,
            state_dir,
            // Unit tests exercise the same ownership checks without root.
            owner_uid: effective_uid(),
        }
    }

    fn sentinel_path(&self) -> PathBuf {
        self.state_dir.join(SENTINEL_NAME)
    }
}

impl<R: CommandRunner> PowerController for SystemPowerController<R> {
    fn ensure_state_directory(&self) -> io::Result<()> {
        ensure_secure_directory(&self.state_dir, self.owner_uid)
    }

    fn fixed_commands_available(&self) -> io::Result<bool> {
        Ok(
            fixed_command_is_secure(Path::new(PMSET))?
                && fixed_command_is_secure(Path::new(IOREG))?,
        )
    }

    fn sleep_disabled(&self) -> io::Result<bool> {
        let output = checked_fixed_output(
            &self.runner,
            IOREG,
            &["-r", "-k", "SleepDisabled", "-d", "4"],
        )?;
        parse_sleep_disabled(&String::from_utf8_lossy(&output.stdout))
    }

    fn set_sleep_disabled(&self, disabled: bool) -> io::Result<()> {
        checked_fixed_output(
            &self.runner,
            PMSET,
            &["-a", "disablesleep", if disabled { "1" } else { "0" }],
        )?;
        let observed = self.sleep_disabled()?;
        if observed != disabled {
            return Err(io::Error::other(format!(
                "SleepDisabled read-back mismatch: requested {disabled}, observed {observed}"
            )));
        }
        Ok(())
    }

    fn battery_state(&self) -> io::Result<BatteryState> {
        let output = checked_fixed_output(&self.runner, PMSET, &["-g", "batt"])?;
        parse_battery_state(&String::from_utf8_lossy(&output.stdout))
    }

    fn lid_closed(&self) -> io::Result<bool> {
        let output = checked_fixed_output(
            &self.runner,
            IOREG,
            &["-r", "-k", "AppleClamshellState", "-d", "4"],
        )?;
        parse_lid_closed(&String::from_utf8_lossy(&output.stdout))
    }

    fn sleep_now(&self) -> io::Result<()> {
        checked_fixed_output(&self.runner, PMSET, &["sleepnow"])?;
        Ok(())
    }

    fn sentinel_exists(&self) -> io::Result<bool> {
        match fs::symlink_metadata(self.sentinel_path()) {
            Ok(metadata) if metadata.file_type().is_symlink() => Err(io::Error::other(
                "refusing symlink at sleepctl sentinel path",
            )),
            Ok(metadata)
                if metadata.is_file()
                    && metadata.uid() == self.owner_uid
                    && metadata.permissions().mode() & 0o077 == 0 =>
            {
                Ok(true)
            }
            Ok(_) => Err(io::Error::other(
                "sleepctl sentinel is not a private file owned by the daemon",
            )),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(error) => Err(error),
        }
    }

    fn write_sentinel(&self, instance_id: &str) -> io::Result<()> {
        self.ensure_state_directory()?;
        let path = self.sentinel_path();
        #[derive(Serialize)]
        struct Sentinel<'a> {
            schema_version: u16,
            instance_id: &'a str,
            baseline_sleep_disabled: bool,
            activated_unix_ms: u128,
        }
        let bytes = serde_json::to_vec(&Sentinel {
            schema_version: 1,
            instance_id,
            baseline_sleep_disabled: false,
            activated_unix_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis(),
        })
        .map_err(io::Error::other)?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        let write_result = file
            .write_all(&bytes)
            .and_then(|()| file.write_all(b"\n"))
            .and_then(|()| file.sync_all())
            .and_then(|()| sync_directory(&self.state_dir));
        if let Err(error) = write_result {
            drop(file);
            let cleanup = fs::remove_file(&path).and_then(|()| sync_directory(&self.state_dir));
            return match cleanup {
                Ok(()) => Err(error),
                Err(cleanup_error) => Err(io::Error::other(format!(
                    "sentinel write failed: {error}; cleanup also failed: {cleanup_error}"
                ))),
            };
        }
        Ok(())
    }

    fn remove_sentinel(&self) -> io::Result<()> {
        let path = self.sentinel_path();
        match fs::remove_file(path) {
            Ok(()) => sync_directory(&self.state_dir),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    fn state_directory_secure(&self) -> io::Result<bool> {
        let metadata = match fs::symlink_metadata(&self.state_dir) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
            Err(error) => return Err(error),
        };
        Ok(metadata.is_dir()
            && !metadata.file_type().is_symlink()
            && metadata.uid() == self.owner_uid
            && metadata.permissions().mode() & 0o077 == 0)
    }
}

fn checked_fixed_output(
    runner: &impl CommandRunner,
    program: &str,
    args: &[&str],
) -> io::Result<Output> {
    if !fixed_command_is_secure(Path::new(program))? {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("{program} is not an immutable root-owned executable"),
        ));
    }
    checked_output(runner, program, args)
}

fn fixed_command_is_secure(path: &Path) -> io::Result<bool> {
    let metadata = fs::symlink_metadata(path)?;
    Ok(metadata.is_file()
        && !metadata.file_type().is_symlink()
        && metadata.uid() == 0
        && metadata.permissions().mode() & 0o111 != 0
        && metadata.permissions().mode() & 0o022 == 0)
}

fn checked_output(runner: &impl CommandRunner, program: &str, args: &[&str]) -> io::Result<Output> {
    let output = runner.output(program, args)?;
    if output.status.success() {
        return Ok(output);
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    let bounded = stderr.chars().take(4_096).collect::<String>();
    Err(io::Error::other(format!(
        "{program} exited with {}: {bounded}",
        output.status
    )))
}

fn ensure_secure_directory(path: &Path, owner_uid: u32) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if !metadata.is_dir()
                || metadata.file_type().is_symlink()
                || metadata.uid() != owner_uid
            {
                return Err(io::Error::other(
                    "sleepctl state path is not a daemon-owned directory",
                ));
            }
            fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            fs::DirBuilder::new().mode(0o700).create(path)
        }
        Err(error) => Err(error),
    }
}

fn sync_directory(path: &Path) -> io::Result<()> {
    OpenOptions::new().read(true).open(path)?.sync_all()
}

#[cfg(test)]
fn effective_uid() -> u32 {
    // SAFETY: geteuid has no arguments and reads process credentials only.
    unsafe { libc::geteuid() }
}

pub(crate) fn parse_sleep_disabled(output: &str) -> io::Result<bool> {
    let lines = output
        .lines()
        .filter(|line| line.contains("\"SleepDisabled\""))
        .collect::<Vec<_>>();
    match lines.as_slice() {
        [line] => parse_ioreg_boolean(line, "SleepDisabled"),
        [] => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "ioreg did not report SleepDisabled",
        )),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "ioreg reported multiple SleepDisabled values",
        )),
    }
}

pub(crate) fn parse_lid_closed(output: &str) -> io::Result<bool> {
    let lines = output
        .lines()
        .filter(|line| line.contains("\"AppleClamshellState\""))
        .collect::<Vec<_>>();
    match lines.as_slice() {
        [line] => parse_ioreg_boolean(line, "AppleClamshellState"),
        [] => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "ioreg did not report AppleClamshellState",
        )),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "ioreg reported multiple AppleClamshellState values",
        )),
    }
}

fn parse_ioreg_boolean(line: &str, key: &str) -> io::Result<bool> {
    let value = line
        .split_once('=')
        .map(|(_, value)| value.trim())
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("ioreg reported malformed {key}"),
            )
        })?;
    match value {
        "Yes" | "1" => Ok(true),
        "No" | "0" => Ok(false),
        _ => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unrecognized {key} value"),
        )),
    }
}

pub(crate) fn parse_battery_state(output: &str) -> io::Result<BatteryState> {
    let source_markers = output
        .lines()
        .filter(|line| line.contains("Now drawing from '"))
        .collect::<Vec<_>>();
    let source = match source_markers.as_slice() {
        [line] if line.contains("'AC Power'") => BatterySource::Ac,
        [line] if line.contains("'Battery Power'") => BatterySource::Battery,
        _ => BatterySource::Unknown,
    };
    let percentages = output
        .lines()
        .filter_map(|line| {
            let index = line.find('%')?;
            let prefix = &line[..index];
            let digits = prefix
                .chars()
                .rev()
                .take_while(char::is_ascii_digit)
                .collect::<String>()
                .chars()
                .rev()
                .collect::<String>();
            digits.parse::<u8>().ok()
        })
        .collect::<Vec<_>>();
    let percent = match percentages.as_slice() {
        [percent] if *percent <= 100 => Some(*percent),
        [] if source == BatterySource::Ac => None,
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "pmset reported invalid or ambiguous battery percentages",
            ));
        }
    };
    if source == BatterySource::Unknown {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "unrecognized pmset battery output",
        ));
    }
    Ok(BatteryState { source, percent })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::os::unix::process::ExitStatusExt;
    use std::sync::Mutex;

    struct FakeRunner {
        outputs: Mutex<VecDeque<Output>>,
    }

    impl CommandRunner for FakeRunner {
        fn output(&self, _program: &str, _args: &[&str]) -> io::Result<Output> {
            self.outputs
                .lock()
                .unwrap()
                .pop_front()
                .ok_or_else(|| io::Error::other("no fake output"))
        }
    }

    fn output(stdout: &str) -> Output {
        Output {
            status: std::process::ExitStatus::from_raw(0),
            stdout: stdout.as_bytes().to_vec(),
            stderr: Vec::new(),
        }
    }

    #[test]
    fn parses_ioreg_booleans() {
        assert!(!parse_sleep_disabled(r#"  |   "SleepDisabled" = No"#).unwrap());
        assert!(parse_sleep_disabled(r#"  |   "SleepDisabled" = Yes"#).unwrap());
        assert!(parse_lid_closed(r#"  |   "AppleClamshellState" = Yes"#).unwrap());
    }

    #[test]
    fn rejects_missing_and_duplicate_sleep_state() {
        assert!(parse_sleep_disabled("").is_err());
        assert!(parse_sleep_disabled("\"SleepDisabled\" = No\n\"SleepDisabled\" = No\n").is_err());
        assert!(parse_sleep_disabled("\"SleepDisabled\" = 10\n").is_err());
        assert!(
            parse_lid_closed("\"AppleClamshellState\" = No\n\"AppleClamshellState\" = Yes\n")
                .is_err()
        );
    }

    #[test]
    fn parses_ac_and_battery_output() {
        assert_eq!(
            parse_battery_state(
                "Now drawing from 'AC Power'\n -InternalBattery-0\t100%; charged;\n"
            )
            .unwrap(),
            BatteryState {
                source: BatterySource::Ac,
                percent: Some(100)
            }
        );
        assert_eq!(
            parse_battery_state(
                "Now drawing from 'Battery Power'\n -InternalBattery-0\t20%; discharging;\n"
            )
            .unwrap(),
            BatteryState {
                source: BatterySource::Battery,
                percent: Some(20)
            }
        );
    }

    #[test]
    fn rejects_invalid_or_ambiguous_battery_output() {
        assert!(
            parse_battery_state(
                "Now drawing from 'Battery Power'\n -InternalBattery-0\t101%; discharging;\n"
            )
            .is_err()
        );
        assert!(
            parse_battery_state(
                "Now drawing from 'AC Power'\nNow drawing from 'Battery Power'\n\
                 -InternalBattery-0\t50%; discharging;\n"
            )
            .is_err()
        );
    }

    #[test]
    fn readback_mismatch_is_an_error() {
        let runner = FakeRunner {
            outputs: Mutex::new(VecDeque::from([
                output(""),
                output("\"SleepDisabled\" = No\n"),
            ])),
        };
        let temp = tempfile::tempdir().unwrap();
        let controller = SystemPowerController::with_runner(runner, temp.path().join("state"));
        assert!(controller.set_sleep_disabled(true).is_err());
    }

    #[test]
    fn sentinel_is_exclusive_and_removed_after_restore() {
        let runner = FakeRunner {
            outputs: Mutex::new(VecDeque::new()),
        };
        let temp = tempfile::tempdir().unwrap();
        let controller = SystemPowerController::with_runner(runner, temp.path().join("state"));
        controller.write_sentinel("one").unwrap();
        assert!(controller.sentinel_exists().unwrap());
        assert!(controller.write_sentinel("two").is_err());
        assert!(controller.state_directory_secure().unwrap());
        controller.remove_sentinel().unwrap();
        assert!(!controller.sentinel_exists().unwrap());
    }

    #[test]
    fn fixed_command_runner_enforces_a_deadline() {
        let _guard = crate::process::PROCESS_TEST_LOCK.lock().unwrap();
        let error = command_output_with_timeout("/bin/sleep", &["1"], Duration::from_millis(10))
            .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
    }

    #[test]
    fn inherited_output_pipe_cannot_extend_the_command_deadline() {
        let _guard = crate::process::PROCESS_TEST_LOCK.lock().unwrap();
        let started = Instant::now();
        let error = command_output_with_timeout(
            "/bin/sh",
            &["-c", "/bin/sleep 60 &"],
            Duration::from_millis(20),
        )
        .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::TimedOut);
        assert!(started.elapsed() < Duration::from_secs(1));
    }
}
