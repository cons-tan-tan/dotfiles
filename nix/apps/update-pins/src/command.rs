use std::collections::BTreeMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::error::UpdateError;

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
    fn is_available(&self, program: &Path) -> bool;
}

#[derive(Clone, Copy, Debug, Default)]
pub struct SystemCommandRunner;

impl CommandRunner for SystemCommandRunner {
    fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
        let mut process = Command::new(&command.program);
        process.args(&command.args).envs(&command.env);
        if let Some(cwd) = &command.cwd {
            process.current_dir(cwd);
        }

        let output = process.output().map_err(|source| UpdateError::Spawn {
            program: command.program.to_string_lossy().into_owned(),
            source,
        })?;
        Ok(CommandOutput {
            status: output.status.code(),
            stdout: output.stdout,
            stderr: output.stderr,
        })
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

pub fn run_checked<R: CommandRunner>(
    runner: &R,
    command: &CommandSpec,
) -> Result<CommandOutput, UpdateError> {
    let output = runner.run(command)?;
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
    use super::{CommandOutput, CommandSpec};

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
}
