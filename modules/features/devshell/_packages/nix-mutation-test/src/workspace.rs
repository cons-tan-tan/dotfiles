use std::collections::VecDeque;
use std::fs;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use tempfile::TempDir;

use crate::model::Candidate;
use crate::mutation;

const MAX_CAPTURE_BYTES: usize = 1024 * 1024;
const POLL_INTERVAL: Duration = Duration::from_millis(10);
const OUTPUT_DRAIN_GRACE: Duration = Duration::from_secs(1);
const TERMINATION_GRACE: Duration = Duration::from_secs(1);

pub struct TestOutput {
    pub status: ExitStatus,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub timed_out: bool,
}

pub struct Workspace {
    _temporary: TempDir,
    snapshot: PathBuf,
    work: PathBuf,
}

impl Workspace {
    pub fn create(root: &Path) -> Result<Self, String> {
        let temporary = tempfile::Builder::new()
            .prefix("nix-mutation-test.")
            .tempdir()
            .map_err(|error| format!("could not create temporary directory: {error}"))?;
        let temporary_path = temporary
            .path()
            .canonicalize()
            .map_err(|error| format!("could not resolve temporary directory: {error}"))?;
        if temporary_path.starts_with(root) {
            return Err("temporary directory must be outside the repository root".to_owned());
        }

        let snapshot = temporary_path.join("snapshot");
        let work = temporary_path.join("work");
        fs::create_dir_all(&snapshot)
            .and_then(|()| fs::create_dir_all(&work))
            .map_err(|error| format!("could not initialize temporary workspace: {error}"))?;
        rsync(root, &snapshot, false)?;

        Ok(Self {
            _temporary: temporary,
            snapshot,
            work,
        })
    }

    pub fn reset(&self) -> Result<(), String> {
        rsync(&self.snapshot, &self.work, true)
    }

    pub fn apply(&self, candidate: &Candidate) -> Result<PathBuf, String> {
        let path = self.work.join(&candidate.file);
        let source = fs::read_to_string(&path)
            .map_err(|error| format!("could not read {}: {error}", path.display()))?;
        let actual_hash = source_hash(&source);
        if actual_hash != candidate.source_hash {
            return Err(format!(
                "{} source hash changed before mutation",
                candidate.id
            ));
        }
        let mutated = mutation::apply(&source, candidate)?;
        fs::write(&path, mutated)
            .map_err(|error| format!("could not write {}: {error}", path.display()))?;
        Ok(path)
    }

    pub fn run_test(
        &self,
        command: &str,
        timeout_seconds: u64,
        mutation_id: &str,
        mutation_kind: &str,
        target: &str,
    ) -> Result<TestOutput, String> {
        let deadline = Instant::now()
            .checked_add(Duration::from_secs(timeout_seconds))
            .ok_or_else(|| "test command timeout is too large".to_owned())?;
        let mut command_process = Command::new("bash");
        command_process
            .arg("-c")
            .arg(command)
            .current_dir(&self.work)
            .env("NIX_MUTATION_ID", mutation_id)
            .env("NIX_MUTATION_KIND", mutation_kind)
            .env("NIX_MUTATION_TARGET", target)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0);
        let mut child = command_process
            .spawn()
            .map_err(|error| format!("could not run test command: {error}"))?;
        let process_group = i32::try_from(child.id())
            .map_err(|_| "test command process ID exceeds i32".to_owned())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "test command stdout was not captured".to_owned())?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| "test command stderr was not captured".to_owned())?;
        if let Err(error) =
            set_nonblocking(stdout.as_raw_fd()).and_then(|()| set_nonblocking(stderr.as_raw_fd()))
        {
            let _ = terminate_process_group(process_group);
            let _ = child.wait();
            return Err(error);
        }
        let stop_readers = Arc::new(AtomicBool::new(false));
        let stdout_reader = bounded_reader(stdout, Arc::clone(&stop_readers));
        let stderr_reader = bounded_reader(stderr, Arc::clone(&stop_readers));
        let wait_result = wait_with_deadline(&mut child, process_group, deadline);
        if wait_result.is_err() {
            let _ = terminate_process_group(process_group);
            let _ = child.wait();
        }
        finish_readers(&stdout_reader, &stderr_reader, &stop_readers);
        let stdout = join_reader(stdout_reader, "stdout")?;
        let stderr = join_reader(stderr_reader, "stderr")?;
        let (status, timed_out) = wait_result?;

        Ok(TestOutput {
            status,
            stdout,
            stderr,
            timed_out,
        })
    }
}

fn wait_with_deadline(
    child: &mut std::process::Child,
    process_group: i32,
    deadline: Instant,
) -> Result<(ExitStatus, bool), String> {
    loop {
        if let Some(status) = child
            .try_wait()
            .map_err(|error| format!("could not inspect test command: {error}"))?
        {
            terminate_process_group(process_group)?;
            return Ok((status, false));
        }
        if Instant::now() >= deadline {
            break;
        }
        thread::sleep(POLL_INTERVAL);
    }

    terminate_process_group(process_group)?;
    let status = child
        .wait()
        .map_err(|error| format!("could not reap timed out test command: {error}"))?;
    Ok((status, true))
}

fn terminate_process_group(process_group: i32) -> Result<(), String> {
    if !process_group_exists(process_group)? {
        return Ok(());
    }
    send_group_signal(process_group, libc::SIGTERM)?;
    let kill_deadline = Instant::now() + TERMINATION_GRACE;
    while Instant::now() < kill_deadline {
        if !process_group_exists(process_group)? {
            return Ok(());
        }
        thread::sleep(POLL_INTERVAL);
    }
    send_group_signal(process_group, libc::SIGKILL)
}

fn send_group_signal(process_group: i32, signal: i32) -> Result<(), String> {
    // SAFETY: kill is called with a valid signal and the negative ID targets
    // only the process group created for this test command.
    if unsafe { libc::kill(-process_group, signal) } == 0 {
        return Ok(());
    }
    let error = std::io::Error::last_os_error();
    if error.raw_os_error() == Some(libc::ESRCH) {
        Ok(())
    } else {
        Err(format!("could not signal timed out test command: {error}"))
    }
}

fn process_group_exists(process_group: i32) -> Result<bool, String> {
    // SAFETY: signal 0 performs existence and permission checks without
    // delivering a signal.
    if unsafe { libc::kill(-process_group, 0) } == 0 {
        return Ok(true);
    }
    let error = std::io::Error::last_os_error();
    match error.raw_os_error() {
        Some(libc::ESRCH) => Ok(false),
        Some(libc::EPERM) => Ok(true),
        _ => Err(format!("could not inspect test process group: {error}")),
    }
}

pub fn parses_with_nix(path: &Path) -> Result<bool, String> {
    Command::new("nix-instantiate")
        .arg("--store")
        .arg("dummy://")
        .arg("--parse")
        .arg(path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .map_err(|error| format!("could not run nix-instantiate: {error}"))
}

fn rsync(source: &Path, destination: &Path, delete: bool) -> Result<(), String> {
    let mut command = Command::new("rsync");
    command.arg("--archive");
    if delete {
        command.arg("--delete");
    }
    command.arg(source.join("."));
    command.arg(destination.join("."));
    let status = command
        .status()
        .map_err(|error| format!("could not run rsync: {error}"))?;
    if !status.success() {
        return Err(format!(
            "rsync failed with status {}",
            status.code().unwrap_or(1)
        ));
    }
    Ok(())
}

fn source_hash(source: &str) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(source.as_bytes())
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn set_nonblocking(file_descriptor: i32) -> Result<(), String> {
    // SAFETY: fcntl is called for a pipe owned by this process, first to read
    // its flags and then to add O_NONBLOCK without changing other flags.
    let flags = unsafe { libc::fcntl(file_descriptor, libc::F_GETFL) };
    if flags == -1 {
        return Err(format!(
            "could not inspect test command output pipe: {}",
            std::io::Error::last_os_error()
        ));
    }
    if unsafe { libc::fcntl(file_descriptor, libc::F_SETFL, flags | libc::O_NONBLOCK) } == -1 {
        return Err(format!(
            "could not configure test command output pipe: {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

fn bounded_reader(
    mut reader: impl Read + Send + 'static,
    stop: Arc<AtomicBool>,
) -> thread::JoinHandle<Result<Vec<u8>, String>> {
    thread::spawn(move || {
        let mut tail = VecDeque::<u8>::with_capacity(MAX_CAPTURE_BYTES);
        let mut buffer = [0_u8; 8192];
        let mut truncated = false;
        loop {
            if stop.load(Ordering::Acquire) {
                break;
            }
            let read = match reader.read(&mut buffer) {
                Ok(read) => read,
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(POLL_INTERVAL);
                    continue;
                }
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(error) => {
                    return Err(format!("could not read test command output: {error}"));
                }
            };
            if read == 0 {
                break;
            }
            let overflow = tail
                .len()
                .saturating_add(read)
                .saturating_sub(MAX_CAPTURE_BYTES);
            if overflow > 0 {
                truncated = true;
                tail.drain(..overflow.min(tail.len()));
            }
            tail.extend(&buffer[..read]);
        }
        let mut output = if truncated {
            b"[... output truncated ...]\n".to_vec()
        } else {
            Vec::new()
        };
        output.extend(tail);
        Ok(output)
    })
}

fn finish_readers(
    stdout: &thread::JoinHandle<Result<Vec<u8>, String>>,
    stderr: &thread::JoinHandle<Result<Vec<u8>, String>>,
    stop: &AtomicBool,
) {
    let deadline = Instant::now() + OUTPUT_DRAIN_GRACE;
    while !(stdout.is_finished() && stderr.is_finished()) && Instant::now() < deadline {
        thread::sleep(POLL_INTERVAL);
    }
    stop.store(true, Ordering::Release);
}

fn join_reader(
    reader: thread::JoinHandle<Result<Vec<u8>, String>>,
    stream: &str,
) -> Result<Vec<u8>, String> {
    reader
        .join()
        .map_err(|_| format!("test command {stream} reader panicked"))?
}
