use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::{Duration, Instant};

use tempfile::{TempDir, tempdir};

struct Fixture {
    work: TempDir,
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
            work,
            baseline: baseline_path,
            target: target_path,
        }
    }

    fn login_command(&self, mode: &str) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_aws-config-helper"));
        command
            .args(["login", "--aws-bin"])
            .arg(env!("CARGO_BIN_EXE_aws-config-helper-aws-fixture"))
            .arg("--baseline")
            .arg(&self.baseline)
            .arg("--target")
            .arg(&self.target)
            .args(["--", "--profile", "test"])
            .env("AWS_CONFIG_HELPER_FIXTURE_MODE", mode);
        command
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

fn wait_for_path(path: &Path) {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !path.exists() {
        assert!(
            Instant::now() < deadline,
            "timed out waiting for {}",
            path.display()
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn successful_login_preserves_target_only_changes_and_exact_child_argv() {
    let fixture = Fixture::new(
        b"[profile test]\r\noutput = json\r\n",
        b"[profile test]\r\ncredential_process = command\r\n# keep\r\n",
    );
    fs::set_permissions(&fixture.target, fs::Permissions::from_mode(0o644)).unwrap();
    let argv = fixture.work.path().join("argv");

    let output = fixture
        .login_command("success")
        .env("AWS_CONFIG_HELPER_FIXTURE_ARGV", &argv)
        .output()
        .unwrap();

    assert_success(&output);
    assert_eq!(
        fs::read(argv).unwrap(),
        b"login\0--profile\0test\0".to_vec()
    );
    let target = fs::read(&fixture.target).unwrap();
    assert!(
        target
            .windows(28)
            .any(|part| part == b"credential_process = command")
    );
    assert!(
        target
            .windows(31)
            .any(|part| part == b"login_session = fixture-session")
    );
    assert!(target.windows(6).any(|part| part == b"# keep"));
    assert_eq!(fs::metadata(&fixture.target).unwrap().mode() & 0o777, 0o600);
    assert!(
        fs::read_dir(fixture.target.parent().unwrap())
            .unwrap()
            .all(|entry| !entry
                .unwrap()
                .file_name()
                .to_string_lossy()
                .starts_with(".aws-config-helper.candidate."))
    );
}

#[test]
fn child_failure_forbidden_diff_and_malformed_candidate_leave_target_unchanged() {
    for (mode, expected_status) in [("fail", 7), ("forbidden", 1), ("malformed", 1)] {
        let fixture = Fixture::new(
            b"[profile test]\noutput = json\n",
            b"[profile test]\ncredential_process = command\n",
        );
        let before = fs::read(&fixture.target).unwrap();
        let inode = fs::metadata(&fixture.target).unwrap().ino();

        let output = fixture.login_command(mode).output().unwrap();

        assert_eq!(output.status.code(), Some(expected_status), "{mode}");
        assert_eq!(fs::read(&fixture.target).unwrap(), before, "{mode}");
        assert_eq!(
            fs::metadata(&fixture.target).unwrap().ino(),
            inode,
            "{mode}"
        );
        assert!(
            !String::from_utf8_lossy(&output.stderr).contains("fixture-session"),
            "{mode}"
        );
    }
}

#[test]
fn prompted_region_is_added_without_reapplying_baseline_keys() {
    let fixture = Fixture::new(b"[profile test]\r\noutput = json\r\n", b"# user file\r\n");

    let output = fixture.login_command("prompt-region").output().unwrap();

    assert_success(&output);
    assert_eq!(
        fs::read_to_string(&fixture.target).unwrap(),
        concat!(
            "# user file\r\n",
            "\r\n",
            "[profile test]\r\n",
            "login_session = fixture-session\r\n",
            "region = ap-northeast-1\r\n",
        )
    );
}

#[test]
fn reconcile_restores_only_managed_sessions_and_is_idempotent() {
    let fixture = Fixture::new(
        b"[profile test]\nregion = baseline\ncredential_process = command\n",
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

    let login = fixture.login_command("success").output().unwrap();
    let reconcile = fixture.reconcile_command().output().unwrap();

    assert_eq!(login.status.code(), Some(1));
    assert_eq!(reconcile.status.code(), Some(1));
    assert_eq!(fs::read(&fixture.target).unwrap(), before);
}

#[test]
fn login_and_reconcile_serialize_without_losing_the_session() {
    let fixture = Fixture::new(
        b"[profile test]\noutput = json\ncredential_process = command\n",
        b"[profile test]\ncredential_process = command\n",
    );
    let ready = fixture.work.path().join("ready");
    let release = fixture.work.path().join("release");
    let mut login = fixture
        .login_command("wait")
        .env("AWS_CONFIG_HELPER_FIXTURE_READY", &ready)
        .env("AWS_CONFIG_HELPER_FIXTURE_RELEASE", &release)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    wait_for_path(&ready);

    let mut reconcile = fixture
        .reconcile_command()
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    std::thread::sleep(Duration::from_millis(100));
    let blocked = reconcile.try_wait().unwrap().is_none();
    fs::write(&release, b"release").unwrap();

    let login_status = login.wait().unwrap();
    let reconcile_status = reconcile.wait().unwrap();
    assert!(blocked, "reconcile did not wait for the login lock");
    assert!(login_status.success());
    assert!(reconcile_status.success());
    let target = fs::read(&fixture.target).unwrap();
    assert!(
        target
            .windows(31)
            .any(|part| part == b"login_session = fixture-session")
    );
    assert!(
        target
            .windows(28)
            .any(|part| part == b"credential_process = command")
    );
}
