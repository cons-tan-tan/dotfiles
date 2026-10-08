use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::PathBuf;
use std::process::{Command, Output};

use tempfile::{TempDir, tempdir};

struct Fixture {
    _work: TempDir,
    baseline: PathBuf,
    target: PathBuf,
}

impl Fixture {
    fn new(baseline: &[u8], target: &[u8]) -> Self {
        let work = tempdir().unwrap();
        let baseline_path = work.path().join("baseline");
        let target_path = work.path().join("home/.aws/config");
        fs::create_dir_all(target_path.parent().unwrap()).unwrap();
        fs::write(&baseline_path, baseline).unwrap();
        fs::write(&target_path, target).unwrap();
        Self {
            _work: work,
            baseline: baseline_path,
            target: target_path,
        }
    }

    fn reconcile_command(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_aws-config-helper"));
        command
            .arg("reconcile")
            .arg("--baseline")
            .arg(&self.baseline)
            .arg("--target")
            .arg(&self.target)
            .args(["--managed-section", "profile test"]);
        command
    }
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "status: {:?}\nstdout: {}\nstderr: {}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn reconcile_restores_only_managed_sessions_and_is_idempotent() {
    let fixture = Fixture::new(
        b"[profile test]\nregion = baseline\noutput = json\n",
        concat!(
            "[profile test]\n",
            "region = user-change\n",
            "login_session = fixture-session\n",
            "\n",
            "[profile unknown]\n",
            "login_session = remove\n",
        )
        .as_bytes(),
    );
    fs::set_permissions(&fixture.target, fs::Permissions::from_mode(0o644)).unwrap();

    let first = fixture.reconcile_command().output().unwrap();
    assert_success(&first);
    let desired = fs::read(&fixture.target).unwrap();
    assert!(desired.windows(17).any(|part| part == b"region = baseline"));
    assert!(
        desired
            .windows(31)
            .any(|part| part == b"login_session = fixture-session")
    );
    assert!(!desired.windows(7).any(|part| part == b"unknown"));
    assert_eq!(fs::metadata(&fixture.target).unwrap().mode() & 0o777, 0o600);
    let inode = fs::metadata(&fixture.target).unwrap().ino();

    let second = fixture.reconcile_command().output().unwrap();
    assert_success(&second);
    assert_eq!(fs::read(&fixture.target).unwrap(), desired);
    assert_eq!(fs::metadata(&fixture.target).unwrap().ino(), inode);
}

#[test]
fn malformed_target_is_never_replaced() {
    let fixture = Fixture::new(
        b"[profile test]\noutput = json\n",
        b"[profile test]\nmalformed\n",
    );
    let before = fs::read(&fixture.target).unwrap();

    let reconcile = fixture.reconcile_command().output().unwrap();

    assert_eq!(reconcile.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&reconcile.stderr).contains("invalid AWS config"));
    assert_eq!(fs::read(&fixture.target).unwrap(), before);
}
