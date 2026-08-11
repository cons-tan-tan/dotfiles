use std::env;
use std::ffi::OsString;
use std::io::{self, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::cli::{self, Action, Options};
use crate::config::Config;
use crate::error::{AppError, Result};
use crate::{diff, filesystem, include, managed_block, privilege};

struct Evaluation {
    current: Vec<u8>,
    desired: Vec<u8>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RestartStyle {
    Macos,
    LinuxSystemd,
    LinuxOther,
    Other,
}

pub trait Runtime {
    fn needs_elevation(&mut self, target: &Path) -> Result<bool> {
        privilege::needs_elevation(target)
    }

    fn ensure_sudo(&mut self, path: &Path) -> Result<()> {
        privilege::ensure_executable(path)
    }

    fn current_executable(&mut self) -> io::Result<PathBuf>;

    /// A successful production call never returns because `exec` replaces this process.
    /// Test runtimes return the child status to model that replacement boundary.
    fn exec(&mut self, program: &Path, arguments: &[OsString]) -> io::Result<u8>;

    fn before_lock(&mut self) {}

    fn restart_style(&self) -> RestartStyle;
}

pub struct SystemRuntime;

impl Runtime for SystemRuntime {
    fn current_executable(&mut self) -> io::Result<PathBuf> {
        env::current_exe()
    }

    fn exec(&mut self, program: &Path, arguments: &[OsString]) -> io::Result<u8> {
        let error = Command::new(program).args(arguments).exec();
        Err(error)
    }

    fn restart_style(&self) -> RestartStyle {
        match env::consts::OS {
            "macos" => RestartStyle::Macos,
            "linux" if Path::new("/run/systemd/system").is_dir() => RestartStyle::LinuxSystemd,
            "linux" => RestartStyle::LinuxOther,
            _ => RestartStyle::Other,
        }
    }
}

pub fn run(
    config: &Config,
    arguments: &[OsString],
    stdout: &mut dyn Write,
    stderr: &mut dyn Write,
    runtime: &mut dyn Runtime,
) -> Result<u8> {
    let action = match cli::parse(arguments) {
        Ok(action) => action,
        Err(error) => {
            write_line(stderr, &error.to_string(), "write argument error")?;
            write_bytes(stderr, cli::USAGE.as_bytes(), "write usage")?;
            return Ok(2);
        }
    };
    if action == Action::Help {
        write_bytes(stdout, cli::USAGE.as_bytes(), "write usage")?;
        return Ok(0);
    }
    let Action::Run(options) = action else {
        unreachable!();
    };
    execute(config, options, arguments, stdout, stderr, runtime)
}

pub fn execute(
    config: &Config,
    options: Options,
    original_arguments: &[OsString],
    stdout: &mut dyn Write,
    stderr: &mut dyn Write,
    runtime: &mut dyn Runtime,
) -> Result<u8> {
    let evaluation = evaluate(config, &config.target)?;
    if evaluation.current == evaluation.desired {
        write_line(
            stdout,
            &format!(
                "apply-nix-settings: {} is already up to date",
                config.target.display()
            ),
            "write status",
        )?;
        return Ok(0);
    }
    if options.check {
        write_line(
            stderr,
            &format!(
                "apply-nix-settings: {} is not up to date",
                config.target.display()
            ),
            "write check status",
        )?;
        print_diff(&evaluation, &config.target, stdout)?;
        return Ok(1);
    }
    if options.dry_run {
        print_diff(&evaluation, &config.target, stdout)?;
        return Ok(0);
    }

    if runtime.needs_elevation(&config.target)? && !config.elevated {
        runtime.ensure_sudo(&config.sudo)?;
        return exec_sudo(config, original_arguments, runtime);
    }

    runtime.before_lock();
    let lock = filesystem::TargetLock::acquire(&config.target)?;
    let evaluation = evaluate(config, lock.target())?;
    if evaluation.current == evaluation.desired {
        write_line(
            stdout,
            &format!(
                "apply-nix-settings: {} is already up to date",
                config.target.display()
            ),
            "write status",
        )?;
        return Ok(0);
    }
    lock.replace(&evaluation.desired)?;
    write_line(
        stdout,
        &format!("apply-nix-settings: wrote {}", config.target.display()),
        "write status",
    )?;
    print_restart_guidance(stdout, runtime.restart_style())?;
    Ok(0)
}

fn evaluate(config: &Config, target: &Path) -> Result<Evaluation> {
    let snippet = filesystem::read_snippet(&config.snippet)?;
    if config.include_required() {
        include::validate(&config.nix_conf, target)?;
    }
    let current = filesystem::read_target(target)?;
    let desired = managed_block::render_desired(&current, &snippet).map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: malformed managed block in {}: {error}",
            target.display()
        ))
    })?;
    Ok(Evaluation { current, desired })
}

fn print_diff(evaluation: &Evaluation, target: &Path, stdout: &mut dyn Write) -> Result<()> {
    let output = diff::unified(&evaluation.current, &evaluation.desired, target);
    write_bytes(stdout, output.as_bytes(), "write diff")
}

fn exec_sudo(
    config: &Config,
    original_arguments: &[OsString],
    runtime: &mut dyn Runtime,
) -> Result<u8> {
    let executable = runtime.current_executable().map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: cannot resolve current executable: {error}"
        ))
    })?;
    let mut arguments = config.sudo_assignments();
    arguments.push(executable.into_os_string());
    arguments.extend_from_slice(original_arguments);
    runtime.exec(&config.sudo, &arguments).map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: cannot execute {}: {error}",
            config.sudo.display()
        ))
    })
}

fn print_restart_guidance(stdout: &mut dyn Write, style: RestartStyle) -> Result<()> {
    write_line(
        stdout,
        "apply-nix-settings: restart the Nix daemon for changes to take effect",
        "write restart guidance",
    )?;
    match style {
        RestartStyle::Macos => write_line(
            stdout,
            "  sudo launchctl kickstart -k system/org.nixos.nix-daemon",
            "write restart guidance",
        ),
        RestartStyle::LinuxSystemd => write_line(
            stdout,
            "  sudo systemctl restart nix-daemon.service",
            "write restart guidance",
        ),
        RestartStyle::LinuxOther => write_line(
            stdout,
            "  restart the WSL distro, or restart nix-daemon using your distro's service manager",
            "write restart guidance",
        ),
        RestartStyle::Other => Ok(()),
    }
}

fn write_line(writer: &mut dyn Write, value: &str, operation: &str) -> Result<()> {
    writer
        .write_all(value.as_bytes())
        .and_then(|()| writer.write_all(b"\n"))
        .and_then(|()| writer.flush())
        .map_err(|error| AppError::new(format!("apply-nix-settings: cannot {operation}: {error}")))
}

fn write_bytes(writer: &mut dyn Write, value: &[u8], operation: &str) -> Result<()> {
    writer
        .write_all(value)
        .and_then(|()| writer.flush())
        .map_err(|error| AppError::new(format!("apply-nix-settings: cannot {operation}: {error}")))
}
