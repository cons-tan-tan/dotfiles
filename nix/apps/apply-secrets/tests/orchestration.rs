#![cfg(feature = "test-fixture")]

use std::ffi::OsString;
use std::fs::{self, Permissions};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::{Value, json};
use tempfile::TempDir;

const END_INVOCATION: u32 = u32::MAX;

struct Harness {
    _temp: TempDir,
    root: PathBuf,
    home: PathBuf,
    manifest: PathBuf,
    log: PathBuf,
}

impl Harness {
    fn new() -> Self {
        let temp = TempDir::new().unwrap();
        let root = temp.path().join("root");
        let home = temp.path().join("home");
        fs::create_dir_all(root.join("secrets")).unwrap();
        fs::create_dir(&home).unwrap();
        Self {
            manifest: temp.path().join("manifest.json"),
            log: temp.path().join("sops-invocations"),
            _temp: temp,
            root,
            home,
        }
    }

    fn source(&self, name: &str, content: &[u8]) -> PathBuf {
        let path = self.root.join("secrets").join(name);
        fs::write(&path, content).unwrap();
        path
    }

    fn write_manifest(&self, entries: Value) {
        fs::write(&self.manifest, serde_json::to_vec(&entries).unwrap()).unwrap();
    }

    fn command(&self) -> Command {
        let mut command = Command::new(apply_secrets());
        command.env("HOME", &self.home);
        command.env("APPLY_SECRETS_ROOT", &self.root);
        command.env("APPLY_SECRETS_MANIFEST", &self.manifest);
        command.env("APPLY_SECRETS_SOPS_BIN", sops_fixture());
        command.env("APPLY_SECRETS_FIXTURE_LOG", &self.log);
        command
    }

    fn run(&self, arguments: &[&str]) -> Output {
        self.command().args(arguments).output().unwrap()
    }

    fn invocations(&self) -> Vec<Vec<Vec<u8>>> {
        if !self.log.exists() {
            return Vec::new();
        }
        decode_invocations(&fs::read(&self.log).unwrap())
    }
}

fn apply_secrets() -> &'static str {
    env!("CARGO_BIN_EXE_apply-secrets")
}

fn sops_fixture() -> &'static str {
    env!("CARGO_BIN_EXE_apply-secrets-sops-test-fixture")
}

fn raw_entry(source: &str, destination: &str) -> Value {
    json!({
        "src": format!("secrets/{source}"),
        "dst": destination,
        "mode": "600",
        "dirMode": "700",
    })
}

fn ssh_entry(source: &str, destination: &str) -> Value {
    json!({
        "src": format!("secrets/{source}"),
        "dst": destination,
        "format": "ssh-config-yaml",
        "mode": "600",
        "dirMode": "700",
    })
}

fn mode(path: &Path) -> u32 {
    fs::metadata(path).unwrap().permissions().mode() & 0o777
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn expected_invocation(source: &Path, ssh: bool) -> Vec<Vec<u8>> {
    let mut arguments = vec![b"--decrypt".to_vec()];
    if ssh {
        arguments.extend([b"--output-type".to_vec(), b"json".to_vec()]);
    }
    arguments.push(source.as_os_str().as_bytes().to_vec());
    arguments
}

fn decode_invocations(bytes: &[u8]) -> Vec<Vec<Vec<u8>>> {
    let mut cursor = 0usize;
    let mut invocations = Vec::new();
    let mut invocation = Vec::new();
    while cursor < bytes.len() {
        let end = cursor.checked_add(4).expect("record length overflow");
        let encoded: [u8; 4] = bytes[cursor..end].try_into().expect("complete log record");
        cursor = end;
        let length = u32::from_le_bytes(encoded);
        if length == END_INVOCATION {
            invocations.push(std::mem::take(&mut invocation));
            continue;
        }
        let length = usize::try_from(length).unwrap();
        let end = cursor
            .checked_add(length)
            .expect("argument length overflow");
        invocation.push(bytes[cursor..end].to_vec());
        cursor = end;
    }
    assert!(invocation.is_empty(), "unterminated invocation log");
    invocations
}

#[test]
fn raw_secret_uses_exact_sops_argv_and_real_filesystem_permissions() {
    let harness = Harness::new();
    let source = harness.source("raw.enc", b"RAW\nfixture raw output");
    fs::create_dir(harness.home.join(".ssh")).unwrap();
    fs::set_permissions(harness.home.join(".ssh"), Permissions::from_mode(0o755)).unwrap();
    harness.write_manifest(json!([raw_entry("raw.enc", ".ssh/config.d/private.conf")]));

    let output = harness.run(&[]);

    assert!(output.status.success(), "{}", stderr(&output));
    let destination = harness.home.join(".ssh/config.d/private.conf");
    assert_eq!(fs::read(&destination).unwrap(), b"fixture raw output");
    assert_eq!(mode(&destination), 0o600);
    assert_eq!(mode(&harness.home.join(".ssh/config.d")), 0o700);
    assert_eq!(mode(&harness.home.join(".ssh")), 0o755);
    assert_eq!(
        harness.invocations(),
        vec![expected_invocation(&source, false)]
    );
    assert!(
        !output
            .stdout
            .windows(b"fixture raw output".len())
            .any(|window| { window == b"fixture raw output" })
    );
    assert!(
        !output
            .stderr
            .windows(b"fixture raw output".len())
            .any(|window| { window == b"fixture raw output" })
    );
}

#[test]
fn ssh_renderer_uses_json_output_and_writes_expected_config() {
    let harness = Harness::new();
    let source = harness.source(
        "ssh.enc",
        br#"JSON
{"hosts":[
  {"host_unencrypted":"work","options":{"HostName":"192.0.2.10","Port":2222}},
  {"patterns_unencrypted":["lab","lab.local"],"options":{"User":"alice","ForwardAgent":false}}
]}"#,
    );
    harness.write_manifest(json!([ssh_entry("ssh.enc", ".ssh/config.d/private.conf")]));

    let output = harness.run(&[]);

    assert!(output.status.success(), "{}", stderr(&output));
    assert_eq!(
        fs::read_to_string(harness.home.join(".ssh/config.d/private.conf")).unwrap(),
        "\
# Managed by apply-secrets - do not edit directly

Host work
    HostName 192.0.2.10
    Port 2222

Host lab lab.local
    User alice
    ForwardAgent no

"
    );
    assert_eq!(
        harness.invocations(),
        vec![expected_invocation(&source, true)]
    );
}

#[test]
fn dry_run_preflights_without_starting_sops_or_mutating_filesystem() {
    let harness = Harness::new();
    harness.source("raw.enc", b"RAW\nunused output");
    harness.write_manifest(json!([raw_entry("raw.enc", ".ssh/config.d/private.conf")]));

    let output = harness.run(&["--dry-run"]);

    assert!(output.status.success(), "{}", stderr(&output));
    assert!(stdout(&output).contains("would write"));
    assert!(harness.invocations().is_empty());
    assert!(!harness.home.join(".ssh").exists());

    harness.write_manifest(json!([
        raw_entry("raw.enc", ".ssh/config.d/first"),
        raw_entry("missing.enc", ".ssh/config.d/second"),
    ]));
    let invalid = harness.run(&["--dry-run"]);
    assert_eq!(invalid.status.code(), Some(1));
    assert!(harness.invocations().is_empty());
    assert!(!harness.home.join(".ssh").exists());
}

#[test]
fn decryption_and_rendering_failures_are_soft_and_later_entries_continue() {
    let harness = Harness::new();
    let failed = harness.source("failed.enc", b"FAIL\n");
    let malformed = harness.source("malformed.enc", b"JSON\nnot valid json");
    let later = harness.source("later.enc", b"RAW\nlater output");
    harness.write_manifest(json!([
        raw_entry("failed.enc", ".secrets/failed"),
        ssh_entry("malformed.enc", ".secrets/malformed"),
        raw_entry("later.enc", ".secrets/later"),
    ]));

    let output = harness.run(&[]);

    assert!(output.status.success(), "{}", stderr(&output));
    assert_eq!(
        fs::read(harness.home.join(".secrets/later")).unwrap(),
        b"later output"
    );
    assert!(!harness.home.join(".secrets/failed").exists());
    assert!(!harness.home.join(".secrets/malformed").exists());
    let errors = stderr(&output);
    assert!(errors.contains("decryption/rendering of secrets/failed.enc failed"));
    assert!(errors.contains("decryption/rendering of secrets/malformed.enc failed"));
    assert!(errors.contains("2 file(s) skipped"));
    assert!(!errors.contains("synthetic decryption failure"));
    assert!(!errors.contains("not valid json"));
    assert!(!errors.contains("later output"));
    assert_eq!(
        harness.invocations(),
        vec![
            expected_invocation(&failed, false),
            expected_invocation(&malformed, true),
            expected_invocation(&later, false),
        ]
    );
}

#[test]
fn spawn_failures_for_all_entries_are_soft_and_exit_successfully() {
    let harness = Harness::new();
    harness.source("one.enc", b"RAW\nfirst output");
    harness.source("two.enc", b"RAW\nsecond output");
    harness.write_manifest(json!([
        raw_entry("one.enc", ".secrets/one"),
        raw_entry("two.enc", ".secrets/two"),
    ]));
    let missing_sops = harness.root.join("missing-sops");

    let output = harness
        .command()
        .env("APPLY_SECRETS_SOPS_BIN", missing_sops)
        .output()
        .unwrap();

    assert!(output.status.success(), "{}", stderr(&output));
    assert!(stderr(&output).contains("2 file(s) skipped"));
    assert!(!harness.home.join(".secrets").exists());
    assert!(harness.invocations().is_empty());
}

#[test]
fn all_successful_entries_exit_zero_without_a_skip_summary() {
    let harness = Harness::new();
    harness.source("one.enc", b"RAW\nfirst output");
    harness.source("two.enc", b"RAW\nsecond output");
    harness.write_manifest(json!([
        raw_entry("one.enc", ".secrets/one"),
        raw_entry("two.enc", ".secrets/two"),
    ]));

    let output = harness.run(&[]);

    assert!(output.status.success(), "{}", stderr(&output));
    assert_eq!(
        fs::read(harness.home.join(".secrets/one")).unwrap(),
        b"first output"
    );
    assert_eq!(
        fs::read(harness.home.join(".secrets/two")).unwrap(),
        b"second output"
    );
    assert!(!stderr(&output).contains("skipped"));
    assert_eq!(harness.invocations().len(), 2);
}

#[test]
fn filesystem_publish_failure_is_hard_stops_later_entries_and_keeps_prior_success() {
    let harness = Harness::new();
    harness.source("first.enc", b"RAW\nfirst output");
    harness.source("blocked.enc", b"RAW\nblocked output");
    harness.source("later.enc", b"RAW\nlater output");
    harness.write_manifest(json!([
        raw_entry("first.enc", "published/first"),
        raw_entry("blocked.enc", "published/blocked"),
        raw_entry("later.enc", "published/later"),
    ]));
    let blocked = harness.home.join("published/blocked");

    let output = harness
        .command()
        .env("APPLY_SECRETS_FIXTURE_BLOCK_SOURCE", "blocked.enc")
        .env("APPLY_SECRETS_FIXTURE_BLOCK_PATH", &blocked)
        .output()
        .unwrap();

    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        fs::read(harness.home.join("published/first")).unwrap(),
        b"first output"
    );
    assert!(blocked.is_dir());
    assert!(!harness.home.join("published/later").exists());
    assert_eq!(harness.invocations().len(), 2);
    assert!(stderr(&output).contains("not a regular file path"));
    assert!(!stderr(&output).contains("file(s) skipped"));
    let names = fs::read_dir(harness.home.join("published"))
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .collect::<Vec<OsString>>();
    assert!(
        names
            .iter()
            .all(|name| !name.as_os_str().as_bytes().starts_with(b".tmp"))
    );
}

#[test]
fn destination_symlinks_are_rejected_without_starting_sops_or_touching_targets() {
    for parent_symlink in [false, true] {
        let harness = Harness::new();
        harness.source("raw.enc", b"RAW\nreplacement output");
        if parent_symlink {
            let outside = harness.root.join("outside-directory");
            fs::create_dir(&outside).unwrap();
            symlink(&outside, harness.home.join("link")).unwrap();
            harness.write_manifest(json!([raw_entry("raw.enc", "link/private")]));

            let output = harness.run(&[]);
            assert_eq!(output.status.code(), Some(1));
            assert!(!outside.join("private").exists());
        } else {
            let outside = harness.root.join("outside-file");
            fs::write(&outside, b"keep").unwrap();
            symlink(&outside, harness.home.join("private")).unwrap();
            harness.write_manifest(json!([raw_entry("raw.enc", "private")]));

            let output = harness.run(&[]);
            assert_eq!(output.status.code(), Some(1));
            assert_eq!(fs::read(&outside).unwrap(), b"keep");
        }
        assert!(harness.invocations().is_empty());
    }
}

#[test]
fn manifest_preflight_rejects_all_entries_before_any_child_or_write() {
    let harness = Harness::new();
    harness.source("raw.enc", b"RAW\nfirst output");
    harness.write_manifest(json!([
        raw_entry("raw.enc", ".secrets/first"),
        raw_entry("raw.enc", "../escape"),
    ]));

    let output = harness.run(&[]);

    assert_eq!(output.status.code(), Some(1));
    assert!(harness.invocations().is_empty());
    assert!(!harness.home.join(".secrets/first").exists());
}

#[test]
fn cli_help_and_usage_errors_have_process_level_exit_codes() {
    let help = Command::new(apply_secrets())
        .arg("--help")
        .output()
        .unwrap();
    assert!(help.status.success());
    assert!(stdout(&help).starts_with("Usage: apply-secrets"));

    for arguments in [
        vec!["--unknown"],
        vec!["--help", "--unknown"],
        vec!["--dry-run", "--dry-run"],
    ] {
        let output = Command::new(apply_secrets())
            .args(arguments)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(2));
        assert!(stderr(&output).contains("unknown argument"));
    }
}
