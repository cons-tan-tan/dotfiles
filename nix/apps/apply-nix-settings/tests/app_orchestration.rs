use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;

use apply_nix_settings::app::{self, RestartStyle, Runtime};
use apply_nix_settings::cli::Options;
use apply_nix_settings::config::Config;
use apply_nix_settings::error::{AppError, Result};
use apply_nix_settings::managed_block;
use tempfile::{TempDir, tempdir};

struct FakeRuntime {
    elevation: bool,
    sudo_available: bool,
    executable: Option<PathBuf>,
    exec_result: io::Result<u8>,
    exec_call: Option<(PathBuf, Vec<OsString>)>,
    restart_style: RestartStyle,
    before_lock: Option<Box<dyn FnMut() + Send>>,
}

impl Default for FakeRuntime {
    fn default() -> Self {
        Self {
            elevation: false,
            sudo_available: true,
            executable: Some(PathBuf::from("/nix/store/test/bin/apply-nix-settings")),
            exec_result: Ok(0),
            exec_call: None,
            restart_style: RestartStyle::Other,
            before_lock: None,
        }
    }
}

impl Runtime for FakeRuntime {
    fn needs_elevation(&mut self, _target: &Path) -> Result<bool> {
        Ok(self.elevation)
    }

    fn ensure_sudo(&mut self, path: &Path) -> Result<()> {
        if self.sudo_available {
            Ok(())
        } else {
            Err(AppError::new(format!(
                "apply-nix-settings: target requires root, and sudo is not available: {}",
                path.display()
            )))
        }
    }

    fn current_executable(&mut self) -> io::Result<PathBuf> {
        self.executable
            .clone()
            .ok_or_else(|| io::Error::other("injected current executable failure"))
    }

    fn exec(&mut self, program: &Path, arguments: &[OsString]) -> io::Result<u8> {
        self.exec_call = Some((program.to_path_buf(), arguments.to_vec()));
        match &self.exec_result {
            Ok(status) => Ok(*status),
            Err(error) => Err(io::Error::new(error.kind(), error.to_string())),
        }
    }

    fn before_lock(&mut self) {
        if let Some(hook) = &mut self.before_lock {
            hook();
        }
    }

    fn restart_style(&self) -> RestartStyle {
        self.restart_style
    }
}

fn fixture() -> (TempDir, Config) {
    let work = tempdir().unwrap();
    let snippet = work.path().join("snippet.conf");
    fs::write(&snippet, b"managed = new\n").unwrap();
    let config = Config {
        target: work.path().join("nix.custom.conf"),
        nix_conf: work.path().join("unused-nix.conf"),
        nix_conf_explicit: false,
        snippet,
        sudo: PathBuf::from("/test/sudo"),
        elevated: false,
    };
    (work, config)
}

fn run(
    config: &Config,
    arguments: &[&str],
    runtime: &mut FakeRuntime,
) -> (Result<u8>, Vec<u8>, Vec<u8>) {
    let arguments = arguments.iter().map(OsString::from).collect::<Vec<_>>();
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let result = app::run(config, &arguments, &mut stdout, &mut stderr, runtime);
    (result, stdout, stderr)
}

#[test]
fn help_and_unknown_argument_keep_stdio_and_exit_contracts() {
    let (_work, config) = fixture();
    let mut runtime = FakeRuntime::default();

    let (result, stdout, stderr) = run(&config, &["--help", "--unknown"], &mut runtime);
    assert_eq!(result.unwrap(), 0);
    assert!(stdout.starts_with(b"Usage: apply-nix-settings"));
    assert!(stderr.is_empty());

    let (result, stdout, stderr) = run(&config, &["--unknown"], &mut runtime);
    assert_eq!(result.unwrap(), 2);
    assert!(stdout.is_empty());
    assert!(stderr.starts_with(b"apply-nix-settings: unknown argument"));
    assert!(
        stderr
            .windows(b"Usage: apply-nix-settings".len())
            .any(|window| { window == b"Usage: apply-nix-settings" })
    );
}

#[test]
fn check_and_dry_run_do_not_write_lock_or_elevate() {
    for (argument, expected_status, expected_stderr) in
        [("--check", 1, true), ("--dry-run", 0, false)]
    {
        let (work, config) = fixture();
        let missing_parent = work.path().join("missing");
        let config = Config {
            target: missing_parent.join("nix.custom.conf"),
            ..config
        };
        let mut runtime = FakeRuntime {
            elevation: true,
            ..FakeRuntime::default()
        };

        let (result, stdout, stderr) = run(&config, &[argument], &mut runtime);
        assert_eq!(result.unwrap(), expected_status);
        assert!(
            stdout
                .windows(b"+managed = new".len())
                .any(|window| { window == b"+managed = new" })
        );
        assert_eq!(!stderr.is_empty(), expected_stderr);
        assert!(!missing_parent.exists());
        assert!(runtime.exec_call.is_none());
    }
}

#[test]
fn sudo_handoff_preserves_assignments_executable_arguments_and_status() {
    let (_work, config) = fixture();
    let mut runtime = FakeRuntime {
        elevation: true,
        exec_result: Ok(73),
        ..FakeRuntime::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let original = [OsString::from("--future"), OsString::from("value")];

    let status = app::execute(
        &config,
        Options::default(),
        &original,
        &mut stdout,
        &mut stderr,
        &mut runtime,
    )
    .unwrap();

    assert_eq!(status, 73);
    assert!(stdout.is_empty());
    assert!(stderr.is_empty());
    let (program, arguments) = runtime.exec_call.unwrap();
    assert_eq!(program, config.sudo);
    let mut expected = config.sudo_assignments();
    expected.push(OsString::from("/nix/store/test/bin/apply-nix-settings"));
    expected.extend(original);
    assert_eq!(arguments, expected);
}

#[test]
fn sudo_preflight_and_exec_failures_are_distinct_and_create_no_artifacts() {
    for (sudo_available, executable, exec_error, expected) in [
        (
            false,
            Some(PathBuf::from("/test/current")),
            None,
            "sudo is not available",
        ),
        (true, None, None, "cannot resolve current executable"),
        (
            true,
            Some(PathBuf::from("/test/current")),
            Some(io::ErrorKind::PermissionDenied),
            "cannot execute /test/sudo",
        ),
    ] {
        let (work, config) = fixture();
        let target_parent = work.path().join("missing");
        let config = Config {
            target: target_parent.join("nix.custom.conf"),
            ..config
        };
        let mut runtime = FakeRuntime {
            elevation: true,
            sudo_available,
            executable,
            exec_result: exec_error.map_or(Ok(0), |kind| {
                Err(io::Error::new(kind, "injected exec failure"))
            }),
            ..FakeRuntime::default()
        };

        let (result, _stdout, _stderr) = run(&config, &[], &mut runtime);
        assert!(result.unwrap_err().to_string().contains(expected));
        assert!(!target_parent.exists());
        assert!(!work.path().join(".apply-nix-settings.lock").exists());
        assert!(fs::read_dir(work.path()).unwrap().all(|entry| {
            !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".apply-nix-settings.tmp.")
        }));
    }
}

#[test]
fn restart_guidance_is_selected_by_the_runtime() {
    for (style, expected) in [
        (
            RestartStyle::Macos,
            Some("sudo launchctl kickstart -k system/org.nixos.nix-daemon"),
        ),
        (
            RestartStyle::LinuxSystemd,
            Some("sudo systemctl restart nix-daemon.service"),
        ),
        (RestartStyle::LinuxOther, Some("restart the WSL distro")),
        (RestartStyle::Other, None),
    ] {
        let (_work, config) = fixture();
        let mut runtime = FakeRuntime {
            restart_style: style,
            ..FakeRuntime::default()
        };
        let (result, stdout, stderr) = run(&config, &[], &mut runtime);
        assert_eq!(result.unwrap(), 0);
        assert!(stderr.is_empty());
        let stdout = String::from_utf8(stdout).unwrap();
        assert!(stdout.contains("restart the Nix daemon"));
        if let Some(expected) = expected {
            assert!(stdout.contains(expected));
        } else {
            assert_eq!(
                stdout.lines().filter(|line| line.starts_with("  ")).count(),
                0
            );
        }
    }
}

#[test]
fn transaction_rereads_after_blocking_and_avoids_a_second_publish() {
    let (_work, config) = fixture();
    fs::write(&config.target, b"before = keep\n").unwrap();
    let lock_path = config
        .target
        .parent()
        .unwrap()
        .join(".apply-nix-settings.lock");
    let holder = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(lock_path)
        .unwrap();
    holder.lock().unwrap();

    let target = config.target.clone();
    let desired = managed_block::render_desired(b"before = keep\n", b"managed = new\n").unwrap();
    let (preflight_complete, wait_for_preflight) = mpsc::channel();
    let (allow_lock, wait_for_target_change) = mpsc::channel();
    let runtime = FakeRuntime {
        before_lock: Some(Box::new(move || {
            preflight_complete.send(()).unwrap();
            wait_for_target_change.recv().unwrap();
        })),
        ..FakeRuntime::default()
    };
    let writer = thread::spawn(move || {
        let mut runtime = runtime;
        let mut stdout = Vec::new();
        let mut stderr = Vec::new();
        let result = app::execute(
            &config,
            Options::default(),
            &[],
            &mut stdout,
            &mut stderr,
            &mut runtime,
        );
        (result, stdout, stderr)
    });

    wait_for_preflight.recv().unwrap();
    fs::write(&target, &desired).unwrap();
    let published_inode = fs::metadata(&target).unwrap().ino();
    allow_lock.send(()).unwrap();
    holder.unlock().unwrap();

    let (result, stdout, stderr) = writer.join().unwrap();
    assert_eq!(result.unwrap(), 0);
    assert!(stderr.is_empty());
    assert!(
        stdout
            .windows(b"already up to date".len())
            .any(|window| { window == b"already up to date" })
    );
    assert_eq!(fs::metadata(&target).unwrap().ino(), published_inode);
    assert_eq!(fs::read(&target).unwrap(), desired);
}
