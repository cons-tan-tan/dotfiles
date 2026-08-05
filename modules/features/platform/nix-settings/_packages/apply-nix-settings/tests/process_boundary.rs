#![cfg(feature = "test-fixture")]

use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use tempfile::{TempDir, tempdir};

fn program() -> &'static str {
    env!("CARGO_BIN_EXE_apply-nix-settings")
}

fn fixture_program() -> &'static str {
    env!("CARGO_BIN_EXE_apply-nix-settings-test-fixture")
}

fn command(work: &TempDir) -> (Command, PathBuf, PathBuf) {
    let target = work.path().join("nix.custom.conf");
    let snippet = work.path().join("snippet.conf");
    fs::write(&snippet, b"managed = new\n").unwrap();
    let mut command = Command::new(program());
    command
        .env_remove("APPLY_NIX_SETTINGS_ELEVATED")
        .env_remove("APPLY_NIX_SETTINGS_NIX_CONF")
        .env("APPLY_NIX_SETTINGS_CONF", &target)
        .env("APPLY_NIX_SETTINGS_SNIPPET", &snippet);
    (command, target, snippet)
}

fn output_text(output: &Output) -> (String, String) {
    (
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

fn nul_arguments(path: &Path) -> Vec<OsString> {
    fs::read(path)
        .unwrap()
        .split(|byte| *byte == b'\0')
        .filter(|value| !value.is_empty())
        .map(|value| OsStr::from_bytes(value).to_os_string())
        .collect()
}

#[test]
fn help_unknown_check_and_dry_run_keep_process_contracts() {
    let work = tempdir().unwrap();

    let (mut help, _target, _snippet) = command(&work);
    let help = help.arg("--help").output().unwrap();
    let (stdout, stderr) = output_text(&help);
    assert_eq!(help.status.code(), Some(0));
    assert!(stdout.starts_with("Usage: apply-nix-settings"));
    assert!(stderr.is_empty());

    let (mut unknown, _target, _snippet) = command(&work);
    let unknown = unknown.arg("--unknown").output().unwrap();
    let (stdout, stderr) = output_text(&unknown);
    assert_eq!(unknown.status.code(), Some(2));
    assert!(stdout.is_empty());
    assert!(stderr.contains("unknown argument"));
    assert!(stderr.contains("Usage: apply-nix-settings"));

    for (argument, expected_status) in [("--check", 1), ("--dry-run", 0)] {
        let isolated = tempdir().unwrap();
        let (mut command, target, _snippet) = command(&isolated);
        let output = command.arg(argument).output().unwrap();
        let (stdout, stderr) = output_text(&output);
        assert_eq!(output.status.code(), Some(expected_status));
        assert!(stdout.contains("+managed = new"));
        assert_eq!(stderr.contains("not up to date"), argument == "--check");
        assert!(!target.exists());
        assert!(!isolated.path().join(".apply-nix-settings.lock").exists());
    }
}

#[test]
fn sudo_exec_preserves_assignments_current_executable_and_child_status() {
    if unsafe { libc::geteuid() } == 0 {
        return;
    }

    let work = tempdir().unwrap();
    let locked = work.path().join("locked");
    fs::create_dir(&locked).unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).unwrap();
    let target = locked.join("nix.custom.conf");
    let snippet = work.path().join("snippet.conf");
    let arguments = work.path().join("sudo.args");
    let marker = work.path().join("sudo.marker");
    fs::write(&snippet, b"managed = new\n").unwrap();

    let output = Command::new(program())
        .env_remove("APPLY_NIX_SETTINGS_ELEVATED")
        .env_remove("APPLY_NIX_SETTINGS_NIX_CONF")
        .env("APPLY_NIX_SETTINGS_CONF", &target)
        .env("APPLY_NIX_SETTINGS_SNIPPET", &snippet)
        .env("APPLY_NIX_SETTINGS_SUDO", fixture_program())
        .env("APPLY_NIX_SETTINGS_FIXTURE_ARGS", &arguments)
        .env("APPLY_NIX_SETTINGS_FIXTURE_MARKER", &marker)
        .env("APPLY_NIX_SETTINGS_FIXTURE_EXIT", "73")
        .output()
        .unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).unwrap();

    assert_eq!(output.status.code(), Some(73));
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    assert_eq!(fs::read(&marker).unwrap(), b"invoked");
    assert!(!target.exists());
    assert!(!locked.join(".apply-nix-settings.lock").exists());
    assert!(fs::read_dir(&locked).unwrap().all(|entry| {
        !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".apply-nix-settings.tmp.")
    }));

    assert_eq!(
        nul_arguments(&arguments),
        [
            OsString::from("APPLY_NIX_SETTINGS_ELEVATED=1"),
            assignment("APPLY_NIX_SETTINGS_CONF", &target),
            OsString::from("APPLY_NIX_SETTINGS_NIX_CONF=/etc/nix/nix.conf"),
            assignment("APPLY_NIX_SETTINGS_SNIPPET", &snippet),
            assignment("APPLY_NIX_SETTINGS_SUDO", Path::new(fixture_program())),
            OsString::from(program()),
        ]
    );
}

#[test]
fn missing_sudo_is_reported_before_creating_target_artifacts() {
    if unsafe { libc::geteuid() } == 0 {
        return;
    }

    let work = tempdir().unwrap();
    let locked = work.path().join("locked");
    fs::create_dir(&locked).unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).unwrap();
    let target = locked.join("nix.custom.conf");
    let snippet = work.path().join("snippet.conf");
    fs::write(&snippet, b"managed = new\n").unwrap();
    let missing_sudo = work.path().join("missing-sudo");

    let output = Command::new(program())
        .env_remove("APPLY_NIX_SETTINGS_ELEVATED")
        .env_remove("APPLY_NIX_SETTINGS_NIX_CONF")
        .env("APPLY_NIX_SETTINGS_CONF", &target)
        .env("APPLY_NIX_SETTINGS_SNIPPET", &snippet)
        .env("APPLY_NIX_SETTINGS_SUDO", &missing_sudo)
        .output()
        .unwrap();
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).unwrap();

    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("sudo is not available"));
    assert!(!target.exists());
    assert!(!locked.join(".apply-nix-settings.lock").exists());
}

fn assignment(name: &str, value: &Path) -> OsString {
    let mut assignment = OsString::from(name);
    assignment.push("=");
    assignment.push(value);
    assignment
}
