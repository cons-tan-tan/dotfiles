use std::collections::BTreeMap;
use std::ffi::OsString;
use std::io::Read as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::error::UpdateError;

const LIMITED_COMMAND_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandSpec {
    pub program: OsString,
    pub args: Vec<OsString>,
    pub cwd: Option<PathBuf>,
    pub env: BTreeMap<OsString, OsString>,
}

impl CommandSpec {
    pub fn new(program: impl Into<OsString>) -> Self {
        Self {
            program: program.into(),
            args: Vec::new(),
            cwd: None,
            env: BTreeMap::new(),
        }
    }

    pub fn arg(mut self, arg: impl Into<OsString>) -> Self {
        self.args.push(arg.into());
        self
    }

    pub fn args<I, S>(mut self, args: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<OsString>,
    {
        self.args.extend(args.into_iter().map(Into::into));
        self
    }

    pub fn current_dir(mut self, cwd: impl Into<PathBuf>) -> Self {
        self.cwd = Some(cwd.into());
        self
    }

    pub fn env(mut self, key: impl Into<OsString>, value: impl Into<OsString>) -> Self {
        self.env.insert(key.into(), value.into());
        self
    }

    pub fn display(&self) -> String {
        let mut rendered = self.program.to_string_lossy().into_owned();
        for arg in &self.args {
            rendered.push(' ');
            let value = arg.to_string_lossy();
            if value
                .chars()
                .all(|character| character.is_ascii_alphanumeric() || "-_./:".contains(character))
            {
                rendered.push_str(&value);
            } else {
                rendered.push('\'');
                for character in value.chars() {
                    if character == '\'' {
                        rendered.push_str("'\\''");
                    } else {
                        rendered.push(character);
                    }
                }
                rendered.push('\'');
            }
        }
        rendered
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CommandOutput {
    pub status: Option<i32>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl CommandOutput {
    pub fn success(&self) -> bool {
        self.status == Some(0)
    }

    pub fn stdout_utf8(&self, command: &CommandSpec) -> Result<&str, UpdateError> {
        std::str::from_utf8(&self.stdout).map_err(|_| UpdateError::NonUtf8Output {
            command: command.display(),
        })
    }
}

pub trait CommandRunner {
    fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError>;

    fn run_limited(
        &self,
        command: &CommandSpec,
        stdout_limit: usize,
        stderr_limit: usize,
    ) -> Result<CommandOutput, UpdateError> {
        let output = self.run(command)?;
        enforce_output_limits(command, output, stdout_limit, stderr_limit)
    }

    fn is_available(&self, program: &Path) -> bool;
}

#[derive(Clone, Copy, Debug, Default)]
pub struct SystemCommandRunner;

impl CommandRunner for SystemCommandRunner {
    fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
        let output = configured_process(command)
            .output()
            .map_err(|source| UpdateError::Spawn {
                program: command.program.to_string_lossy().into_owned(),
                source,
            })?;
        Ok(CommandOutput {
            status: output.status.code(),
            stdout: output.stdout,
            stderr: output.stderr,
        })
    }

    fn run_limited(
        &self,
        command: &CommandSpec,
        stdout_limit: usize,
        stderr_limit: usize,
    ) -> Result<CommandOutput, UpdateError> {
        let mut process = configured_process(command);
        process.stdout(Stdio::piped()).stderr(Stdio::piped());
        let mut child = process.spawn().map_err(|source| UpdateError::Spawn {
            program: command.program.to_string_lossy().into_owned(),
            source,
        })?;
        let stdout = child.stdout.take().expect("stdout requested as a pipe");
        let stderr = child.stderr.take().expect("stderr requested as a pipe");
        let stdout_reader =
            std::thread::spawn(move || read_at_most(stdout, stdout_limit.saturating_add(1)));
        let stderr_reader =
            std::thread::spawn(move || read_at_most(stderr, stderr_limit.saturating_add(1)));
        let started = Instant::now();
        let (status, timed_out) = loop {
            if let Some(status) = child
                .try_wait()
                .map_err(|source| process_runtime_error(command, "wait for", source))?
            {
                break (status, false);
            }
            if started.elapsed() >= LIMITED_COMMAND_TIMEOUT {
                child
                    .kill()
                    .map_err(|source| process_runtime_error(command, "terminate", source))?;
                let status = child
                    .wait()
                    .map_err(|source| process_runtime_error(command, "reap", source))?;
                break (status, true);
            }
            std::thread::sleep(Duration::from_millis(10));
        };
        let stdout = join_reader(stdout_reader, command, "stdout")?;
        let stderr = join_reader(stderr_reader, command, "stderr")?;
        if timed_out {
            return Err(UpdateError::CommandTimedOut {
                program: command.program.to_string_lossy().into_owned(),
                seconds: LIMITED_COMMAND_TIMEOUT.as_secs(),
            });
        }
        enforce_output_limits(
            command,
            CommandOutput {
                status: status.code(),
                stdout,
                stderr,
            },
            stdout_limit,
            stderr_limit,
        )
    }

    fn is_available(&self, program: &Path) -> bool {
        if program.components().count() > 1 {
            return is_executable(program);
        }

        std::env::var_os("PATH")
            .map(|path| {
                std::env::split_paths(&path)
                    .map(|directory| directory.join(program))
                    .any(|candidate| is_executable(&candidate))
            })
            .unwrap_or(false)
    }
}

fn process_runtime_error(
    command: &CommandSpec,
    operation: &str,
    source: std::io::Error,
) -> UpdateError {
    UpdateError::message(format!(
        "{}: failed to {operation} process: {source}",
        command.display()
    ))
}

fn configured_process(command: &CommandSpec) -> Command {
    let mut process = Command::new(&command.program);
    process.args(&command.args).envs(&command.env);
    if let Some(cwd) = &command.cwd {
        process.current_dir(cwd);
    }
    process
}

fn read_at_most(reader: impl std::io::Read, limit: usize) -> std::io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader.take(limit as u64).read_to_end(&mut bytes)?;
    Ok(bytes)
}

fn join_reader(
    reader: std::thread::JoinHandle<std::io::Result<Vec<u8>>>,
    command: &CommandSpec,
    stream: &str,
) -> Result<Vec<u8>, UpdateError> {
    reader
        .join()
        .map_err(|_| {
            UpdateError::message(format!(
                "{}: {stream} reader thread panicked",
                command.display()
            ))
        })?
        .map_err(|source| {
            UpdateError::message(format!(
                "{}: failed to read {stream}: {source}",
                command.display()
            ))
        })
}

fn enforce_output_limits(
    command: &CommandSpec,
    output: CommandOutput,
    stdout_limit: usize,
    stderr_limit: usize,
) -> Result<CommandOutput, UpdateError> {
    if output.stdout.len() > stdout_limit {
        return Err(UpdateError::message(format!(
            "{}: stdout exceeded {stdout_limit} bytes",
            command.display()
        )));
    }
    if output.stderr.len() > stderr_limit {
        return Err(UpdateError::message(format!(
            "{}: stderr exceeded {stderr_limit} bytes",
            command.display()
        )));
    }
    Ok(output)
}

pub fn run_checked<R: CommandRunner>(
    runner: &R,
    command: &CommandSpec,
) -> Result<CommandOutput, UpdateError> {
    let output = runner.run(command)?;
    require_success(command, output)
}

pub fn run_checked_limited<R: CommandRunner>(
    runner: &R,
    command: &CommandSpec,
    stdout_limit: usize,
    stderr_limit: usize,
) -> Result<CommandOutput, UpdateError> {
    let output = runner.run_limited(command, stdout_limit, stderr_limit)?;
    require_success(command, output)
}

pub fn require_success(
    command: &CommandSpec,
    output: CommandOutput,
) -> Result<CommandOutput, UpdateError> {
    if output.success() {
        return Ok(output);
    }

    let status = output
        .status
        .map_or_else(|| "signal".to_owned(), |code| code.to_string());
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    Err(UpdateError::CommandFailed {
        command: command.display(),
        status,
        stderr,
    })
}

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt as _;

    path.metadata()
        .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.is_file()
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::{CommandOutput, CommandRunner, CommandSpec, run_checked_limited};
    use crate::error::UpdateError;

    struct FixedOutput(CommandOutput);

    impl CommandRunner for FixedOutput {
        fn run(&self, _command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            Ok(self.0.clone())
        }

        fn is_available(&self, _program: &Path) -> bool {
            false
        }
    }

    #[test]
    fn display_quotes_arguments_without_changing_the_stored_argv() {
        let command = CommandSpec::new("nix")
            .args(["flake", "update", "input with spaces"])
            .env("UPDATE_PINS_PACKAGE", "example");

        assert_eq!(command.args[0], "flake");
        assert_eq!(command.args[1], "update");
        assert_eq!(command.args[2], "input with spaces");
        assert_eq!(command.display(), "nix flake update 'input with spaces'");
    }

    #[test]
    fn command_output_only_accepts_zero_as_success() {
        let output = CommandOutput {
            status: Some(0),
            stdout: Vec::new(),
            stderr: Vec::new(),
        };
        assert!(output.success());

        let failed = CommandOutput {
            status: Some(1),
            stdout: Vec::new(),
            stderr: Vec::new(),
        };
        assert!(!failed.success());
    }

    #[test]
    fn limited_execution_rejects_oversized_streams_for_all_runners() {
        let runner = FixedOutput(CommandOutput {
            status: Some(0),
            stdout: b"12345".to_vec(),
            stderr: b"67890".to_vec(),
        });
        let command = CommandSpec::new("example");
        assert!(
            run_checked_limited(&runner, &command, 4, 5)
                .expect_err("oversized stdout")
                .to_string()
                .contains("stdout exceeded 4 bytes")
        );
        assert!(
            run_checked_limited(&runner, &command, 5, 4)
                .expect_err("oversized stderr")
                .to_string()
                .contains("stderr exceeded 4 bytes")
        );
    }
}
