#![cfg(feature = "test-fixture")]

use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TEMP_PATH: AtomicU64 = AtomicU64::new(0);

fn curl_fetch() -> &'static str {
    env!("CARGO_BIN_EXE_curl-fetch")
}

fn gh_api_get() -> &'static str {
    env!("CARGO_BIN_EXE_gh-api-get")
}

fn fixture() -> &'static str {
    env!("CARGO_BIN_EXE_safe-fetch-test-fixture")
}

fn command(program: &str) -> Command {
    let mut command = Command::new(program);
    command.env("SAFE_FETCH_CURL_BIN", fixture());
    command.env("SAFE_FETCH_GH_BIN", fixture());
    command
}

fn argument_hex(output: &Output) -> Vec<&[u8]> {
    output
        .stdout
        .split(|byte| *byte == b'\n')
        .filter_map(|line| line.strip_prefix(b"arg="))
        .collect()
}

fn hex(value: impl AsRef<OsStr>) -> Vec<u8> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    value
        .as_ref()
        .as_bytes()
        .iter()
        .flat_map(|byte| [HEX[usize::from(byte >> 4)], HEX[usize::from(byte & 0x0f)]])
        .collect()
}

fn temporary_marker(name: &str) -> PathBuf {
    let sequence = NEXT_TEMP_PATH.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!(
        "safe-fetch-{name}-{}-{sequence}",
        std::process::id()
    ))
}

fn assert_not_invoked(program: &str, arguments: &[&str], expected_status: i32, marker: &Path) {
    let _ = fs::remove_file(marker);
    let output = command(program)
        .env("SAFE_FETCH_FIXTURE_MARKER", marker)
        .args(arguments)
        .output()
        .expect("run rejected safe-fetch command");

    assert_eq!(output.status.code(), Some(expected_status));
    assert!(
        !marker.exists(),
        "policy rejection must not invoke the child"
    );
}

#[test]
fn curl_fetch_pins_child_prefix_and_preserves_arguments() {
    let output = command(curl_fetch())
        .env("SAFE_FETCH_FIXTURE_PRINT_ARGS", "1")
        .args(["-sL", "-o", "/tmp/result", "https://example.com"])
        .output()
        .unwrap();

    assert!(output.status.success());
    assert_eq!(
        argument_hex(&output),
        [
            "-q",
            "--globoff",
            "--proto",
            "=http,https",
            "--proto-redir",
            "=http,https",
            "-sL",
            "-o",
            "/tmp/result",
            "https://example.com",
        ]
        .map(hex)
    );
}

#[test]
fn gh_api_get_pins_host_and_method() {
    let output = command(gh_api_get())
        .env("SAFE_FETCH_FIXTURE_PRINT_ARGS", "1")
        .args(["repos/o/r/issues", "-F", "state=open"])
        .output()
        .unwrap();

    assert!(output.status.success());
    assert_eq!(
        argument_hex(&output),
        [
            "api",
            "--hostname",
            "github.com",
            "repos/o/r/issues",
            "-F",
            "state=open",
            "--method",
            "GET",
        ]
        .map(hex)
    );
}

#[test]
fn policy_rejections_do_not_invoke_children_and_keep_exit_contracts() {
    let curl_marker = temporary_marker("curl-rejected");
    assert_not_invoked(
        curl_fetch(),
        &["--request", "POST", "https://example.com"],
        1,
        &curl_marker,
    );

    let gh_marker = temporary_marker("gh-rejected");
    assert_not_invoked(
        gh_api_get(),
        &["repos/o/r", "--method", "DELETE"],
        2,
        &gh_marker,
    );
}

#[test]
fn child_stdout_stderr_and_exit_status_are_preserved() {
    for (program, arguments, code) in [
        (curl_fetch(), vec!["https://example.com"], 42),
        (gh_api_get(), vec!["repos/o/r"], 43),
        (curl_fetch(), vec!["https://example.com"], 255),
    ] {
        let output = command(program)
            .env("SAFE_FETCH_FIXTURE_STDOUT", "fixture stdout\n")
            .env("SAFE_FETCH_FIXTURE_STDERR", "fixture stderr\n")
            .env("SAFE_FETCH_FIXTURE_EXIT", code.to_string())
            .args(arguments)
            .output()
            .unwrap();

        assert_eq!(output.status.code(), Some(code));
        assert_eq!(output.stdout, b"fixture stdout\n");
        assert_eq!(output.stderr, b"fixture stderr\n");
    }
}

#[test]
fn non_utf8_arguments_reach_the_child_unchanged() {
    let curl_header = OsString::from_vec(b"X-Test: \xff".to_vec());
    let curl_output = command(curl_fetch())
        .env("SAFE_FETCH_FIXTURE_PRINT_ARGS", "1")
        .arg("--header")
        .arg(&curl_header)
        .arg("https://example.com")
        .output()
        .unwrap();
    assert!(curl_output.status.success());
    assert!(argument_hex(&curl_output).contains(&hex(&curl_header).as_slice()));

    let gh_endpoint = OsString::from_vec(b"repos/o/r/\xff".to_vec());
    let gh_output = command(gh_api_get())
        .env("SAFE_FETCH_FIXTURE_PRINT_ARGS", "1")
        .arg(&gh_endpoint)
        .output()
        .unwrap();
    assert!(gh_output.status.success());
    assert!(argument_hex(&gh_output).contains(&hex(&gh_endpoint).as_slice()));
}

#[test]
fn missing_child_configuration_fails_before_exec() {
    let curl = Command::new(curl_fetch())
        .env_remove("SAFE_FETCH_CURL_BIN")
        .output()
        .unwrap();
    assert_eq!(curl.status.code(), Some(1));
    assert!(curl.stderr.starts_with(b"curl-fetch: SAFE_FETCH_CURL_BIN"));

    let gh = Command::new(gh_api_get())
        .env_remove("SAFE_FETCH_GH_BIN")
        .output()
        .unwrap();
    assert_eq!(gh.status.code(), Some(1));
    assert!(gh.stderr.starts_with(b"gh-api-get: SAFE_FETCH_GH_BIN"));
}
