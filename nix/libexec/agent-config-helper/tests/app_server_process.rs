#![cfg(feature = "test-fixture")]

use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use agent_config_helper::app_server::fetch_hooks_list_with_timeout;
use agent_config_helper::hook_state::build_payload;
use tempfile::TempDir;

const NORMAL_TEST_TIMEOUT: Duration = Duration::from_secs(5);
const STALL_TEST_TIMEOUT: Duration = Duration::from_millis(300);

struct Fixture {
    _directory: TempDir,
    executable: PathBuf,
}

impl Fixture {
    fn new(mode: &str) -> Self {
        let source = Path::new(env!("CARGO_BIN_EXE_agent-config-helper-fixture"));
        assert!(source.is_absolute());
        let directory = tempfile::tempdir().unwrap();
        let executable = directory.path().join(mode);
        let mut source_file = File::open(source).unwrap();
        let mut destination = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&executable)
            .unwrap();
        io::copy(&mut source_file, &mut destination).unwrap();
        destination
            .set_permissions(fs::Permissions::from_mode(0o755))
            .unwrap();
        destination.sync_all().unwrap();
        // Linux rejects exec while any writer still has the copied inode
        // open. Keep the close explicit because these fixtures start in
        // parallel under the full Cargo test suite.
        drop(destination);
        drop(source_file);
        Self {
            _directory: directory,
            executable,
        }
    }

    fn pid(&self) -> u32 {
        self.read_pid(&self.executable.with_extension("pid"))
    }

    fn grandchild_pid(&self) -> u32 {
        self.read_pid(&self.executable.with_extension("grandchild.pid"))
    }

    fn read_pid(&self, path: &Path) -> u32 {
        for _ in 0..100 {
            if let Ok(value) = fs::read_to_string(path) {
                return value.parse().unwrap();
            }
            thread::sleep(Duration::from_millis(5));
        }
        panic!("fixture did not write {}", path.display());
    }
}

fn fetch(
    mode: &str,
) -> (
    Fixture,
    agent_config_helper::error::Result<agent_config_helper::hook_state::HooksListResponse>,
) {
    fetch_with_timeout(mode, NORMAL_TEST_TIMEOUT)
}

fn fetch_with_timeout(
    mode: &str,
    timeout: Duration,
) -> (
    Fixture,
    agent_config_helper::error::Result<agent_config_helper::hook_state::HooksListResponse>,
) {
    let fixture = Fixture::new(mode);
    let cwd = fixture._directory.path().to_path_buf();
    for attempt in 0..10 {
        let result = fetch_hooks_list_with_timeout(&fixture.executable, &cwd, timeout);
        let text_busy = result
            .as_ref()
            .is_err_and(|error| error.to_string().contains("Text file busy"));
        if !text_busy || attempt == 9 {
            return (fixture, result);
        }
        thread::sleep(Duration::from_millis(10));
    }
    unreachable!()
}

fn assert_reaped(pid: u32) {
    // SAFETY: signal 0 performs no mutation; it only checks whether the PID
    // still exists. shutdown waits, so ESRCH also excludes a zombie child.
    for _ in 0..100 {
        let result = unsafe { libc::kill(pid as libc::pid_t, 0) };
        if result == -1 && std::io::Error::last_os_error().raw_os_error() == Some(libc::ESRCH) {
            return;
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("fixture process {pid} is still present");
}

#[test]
fn normal_protocol_returns_typed_hooks_and_reaps_a_lingering_child() {
    let (fixture, result) = fetch("normal");
    let hooks = result.unwrap();
    let pid = fixture.pid();
    assert_eq!(hooks.data.len(), 1);
    let payload = build_payload(
        &hooks,
        "herdr-command",
        Path::new("/home/me/.codex/hooks.json"),
    )
    .unwrap();
    assert_eq!(
        payload["hooks"]["state"]["/home/me/.codex/hooks.json:session_start:1:0"]["trusted_hash"],
        "sha256:from-fixture"
    );
    assert_reaped(pid);
}

#[test]
fn pipe_holding_grandchild_is_terminated_with_the_app_server_group() {
    let (fixture, result) = fetch("grandchild-pipe-holder");
    assert_eq!(result.unwrap().data.len(), 1);
    assert_reaped(fixture.pid());
    assert_reaped(fixture.grandchild_pid());
}

#[test]
fn coalesced_noise_notifications_and_other_ids_are_skipped() {
    let (fixture, result) = fetch("noisy-single-write");
    assert_eq!(result.unwrap().data.len(), 1);
    assert_reaped(fixture.pid());
}

#[test]
fn a_same_id_server_request_is_not_mistaken_for_a_response() {
    let (fixture, result) = fetch("same-id-server-request");
    assert_eq!(result.unwrap().data.len(), 1);
    assert_reaped(fixture.pid());
}

#[test]
fn malformed_matching_envelopes_and_non_object_json_are_rejected() {
    for mode in ["malformed-envelope", "non-object-json"] {
        let (fixture, result) = fetch(mode);
        assert!(result.is_err(), "{mode}");
        assert_reaped(fixture.pid());
    }
}

#[test]
fn rpc_errors_report_code_and_message_but_not_data() {
    let (fixture, result) = fetch("rpc-error");
    let message = result.unwrap_err().to_string();
    assert!(message.contains("-32000"));
    assert!(message.contains("fixture rpc failure"));
    assert!(!message.contains("do not expose this field"));
    assert_reaped(fixture.pid());
}

#[test]
fn eof_and_nonzero_exit_are_reported_and_reaped() {
    let (eof_fixture, eof) = fetch("eof");
    assert!(eof.unwrap_err().to_string().contains("EOF"));
    assert_reaped(eof_fixture.pid());

    let (nonzero_fixture, nonzero) = fetch("nonzero");
    let message = nonzero.unwrap_err().to_string();
    assert!(
        message.contains("exit status: 23") || message.contains("fixture-nonzero-marker"),
        "{message}"
    );
    assert_reaped(nonzero_fixture.pid());
}

#[test]
fn partial_frames_time_out_and_oversized_frames_fail_without_hanging() {
    let (partial_fixture, partial) = fetch_with_timeout("partial-stall", STALL_TEST_TIMEOUT);
    assert!(partial.unwrap_err().to_string().contains("timed out"));
    assert_reaped(partial_fixture.pid());

    let (large_fixture, large) = fetch("oversized-frame");
    assert!(large.unwrap_err().to_string().contains("frame limit"));
    assert_reaped(large_fixture.pid());
}

#[test]
fn stderr_is_continuously_drained_and_error_tail_is_bounded() {
    let (success_fixture, success) = fetch("stderr-flood");
    assert_eq!(success.unwrap().data.len(), 1);
    assert_reaped(success_fixture.pid());

    let (error_fixture, error) = fetch("stderr-flood-error");
    let message = error.unwrap_err().to_string();
    assert!(message.contains("fixture-stderr-tail-marker"));
    assert!(
        message.len() < 9 * 1024,
        "error was {} bytes",
        message.len()
    );
    assert_reaped(error_fixture.pid());
}

#[test]
fn child_closing_stdin_during_the_handshake_is_an_error_not_a_panic() {
    let (fixture, result) = fetch("close-after-initialize");
    assert!(result.is_err());
    assert_reaped(fixture.pid());
}

#[test]
fn relative_codex_binary_paths_are_rejected_before_spawn() {
    let error =
        fetch_hooks_list_with_timeout(Path::new("codex"), Path::new("/tmp"), NORMAL_TEST_TIMEOUT)
            .unwrap_err();
    assert!(error.to_string().contains("absolute path"));
}
