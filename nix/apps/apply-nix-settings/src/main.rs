use std::env;
use std::ffi::OsString;
use std::io::{self, Write};
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, ExitCode};

use apply_nix_settings::cli::{self, Action, Options};
use apply_nix_settings::config::Config;
use apply_nix_settings::error::{AppError, Result};
use apply_nix_settings::{diff, filesystem, include, managed_block, privilege};

struct Evaluation {
    current: Vec<u8>,
    desired: Vec<u8>,
}

fn main() -> ExitCode {
    match run_main() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run_main() -> Result<u8> {
    let config = Config::from_environment()?;
    let arguments: Vec<OsString> = env::args_os().skip(1).collect();
    let action = match cli::parse(&arguments) {
        Ok(action) => action,
        Err(error) => {
            eprintln!("{error}");
            eprint!("{}", cli::USAGE);
            return Ok(2);
        }
    };
    if action == Action::Help {
        print!("{}", cli::USAGE);
        return Ok(0);
    }
    let Action::Run(options) = action else {
        unreachable!();
    };
    run(&config, options, &arguments)
}

fn run(config: &Config, options: Options, original_arguments: &[OsString]) -> Result<u8> {
    run_with_before_lock_hook(config, options, original_arguments, || {})
}

fn run_with_before_lock_hook(
    config: &Config,
    options: Options,
    original_arguments: &[OsString],
    before_lock: impl FnOnce(),
) -> Result<u8> {
    let evaluation = evaluate(config, &config.target)?;
    if evaluation.current == evaluation.desired {
        println!(
            "apply-nix-settings: {} is already up to date",
            config.target.display()
        );
        return Ok(0);
    }
    if options.check {
        eprintln!(
            "apply-nix-settings: {} is not up to date",
            config.target.display()
        );
        print_diff(&evaluation, &config.target)?;
        return Ok(1);
    }
    if options.dry_run {
        print_diff(&evaluation, &config.target)?;
        return Ok(0);
    }

    if privilege::needs_elevation(&config.target)? && !config.elevated {
        privilege::ensure_executable(&config.sudo)?;
        return exec_sudo(config, original_arguments);
    }

    before_lock();
    let lock = filesystem::TargetLock::acquire(&config.target)?;
    let evaluation = evaluate(config, lock.target())?;
    if evaluation.current == evaluation.desired {
        println!(
            "apply-nix-settings: {} is already up to date",
            config.target.display()
        );
        return Ok(0);
    }
    lock.replace(&evaluation.desired)?;
    println!("apply-nix-settings: wrote {}", config.target.display());
    print_restart_guidance();
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

fn print_diff(evaluation: &Evaluation, target: &Path) -> Result<()> {
    let output = diff::unified(&evaluation.current, &evaluation.desired, target);
    let mut stdout = io::stdout().lock();
    stdout.write_all(output.as_bytes()).map_err(|error| {
        AppError::new(format!("apply-nix-settings: cannot write diff: {error}"))
    })?;
    stdout
        .flush()
        .map_err(|error| AppError::new(format!("apply-nix-settings: cannot flush diff: {error}")))
}

fn exec_sudo(config: &Config, original_arguments: &[OsString]) -> Result<u8> {
    let executable = env::current_exe().map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: cannot resolve current executable: {error}"
        ))
    })?;
    let mut command = Command::new(&config.sudo);
    command.args(config.sudo_assignments());
    command.arg(executable);
    command.args(original_arguments);
    let error = command.exec();
    Err(AppError::new(format!(
        "apply-nix-settings: cannot execute {}: {error}",
        config.sudo.display()
    )))
}

fn print_restart_guidance() {
    println!("apply-nix-settings: restart the Nix daemon for changes to take effect");
    match env::consts::OS {
        "macos" => println!("  sudo launchctl kickstart -k system/org.nixos.nix-daemon"),
        "linux" if Path::new("/run/systemd/system").is_dir() => {
            println!("  sudo systemctl restart nix-daemon.service");
        }
        "linux" => {
            println!(
                "  restart the WSL distro, or restart nix-daemon using your distro's service manager"
            );
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fs2::FileExt;
    use std::fs::{self, OpenOptions};
    use std::sync::mpsc;
    use std::thread;
    use tempfile::tempdir;

    #[test]
    fn transaction_rereads_target_after_waiting_for_the_lock() {
        let work = tempdir().unwrap();
        let target = work.path().join("nix.custom.conf");
        let snippet = work.path().join("snippet.conf");
        fs::write(&target, b"before = keep\n").unwrap();
        fs::write(&snippet, b"managed = new\n").unwrap();

        let lock_path = work.path().join(".apply-nix-settings.lock");
        let holder = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)
            .unwrap();
        FileExt::lock_exclusive(&holder).unwrap();

        let config = Config {
            target: target.clone(),
            nix_conf: work.path().join("unused-nix.conf"),
            nix_conf_explicit: false,
            snippet,
            sudo: Path::new("/unused-sudo").to_path_buf(),
            elevated: false,
        };
        let (preflight_complete, wait_for_preflight) = mpsc::channel();
        let (allow_lock, wait_for_target_change) = mpsc::channel();
        let writer = thread::spawn(move || {
            run_with_before_lock_hook(&config, Options::default(), &[], || {
                preflight_complete.send(()).unwrap();
                wait_for_target_change.recv().unwrap();
            })
        });

        wait_for_preflight.recv().unwrap();
        fs::write(&target, b"before = keep\nwhile-waiting = preserve\n").unwrap();
        allow_lock.send(()).unwrap();
        FileExt::unlock(&holder).unwrap();

        assert_eq!(writer.join().unwrap().unwrap(), 0);
        let content = fs::read(&target).unwrap();
        assert!(
            content
                .windows(b"while-waiting = preserve".len())
                .any(|window| window == b"while-waiting = preserve")
        );
        assert!(
            content
                .windows(b"managed = new".len())
                .any(|window| window == b"managed = new")
        );
    }
}
