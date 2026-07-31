use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde_json::{Value, json};
use tempfile::TempDir;

fn helper(arguments: impl IntoIterator<Item = impl AsRef<OsStr>>) -> Output {
    Command::new(env!("CARGO_BIN_EXE_agent-config-helper"))
        .args(arguments)
        .output()
        .unwrap()
}

fn write_json(directory: &TempDir, name: &str, value: &Value) -> PathBuf {
    let path = directory.path().join(name);
    fs::write(&path, serde_json::to_vec_pretty(value).unwrap()).unwrap();
    path
}

fn parse_success(output: Output) -> Value {
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    assert_eq!(output.stdout.last(), Some(&b'\n'));
    assert!(!output.stdout[..output.stdout.len() - 1].contains(&b'\n'));
    serde_json::from_slice(&output.stdout).unwrap()
}

fn path(path: &Path) -> &OsStr {
    path.as_os_str()
}

#[test]
fn claude_commands_read_transform_and_emit_compact_json() {
    let directory = tempfile::tempdir().unwrap();
    let settings = write_json(
        &directory,
        "settings.json",
        &json!({
            "hooks": {
                "SessionStart": [{
                    "hooks": [{"type": "command", "command": "old"}]
                }]
            },
            "env": {"KEEP": "yes"},
            "permissions": {"allow": ["base"]},
            "discarded": true
        }),
    );

    let selected = parse_success(helper([
        OsStr::new("claude"),
        OsStr::new("select-integration"),
        path(&settings),
    ]));
    assert_eq!(
        selected,
        json!({
            "hooks": {
                "SessionStart": [{
                    "hooks": [{"type": "command", "command": "old"}]
                }]
            },
            "env": {"KEEP": "yes"},
            "permissions": {"allow": ["base"]}
        })
    );

    let rewritten = parse_success(helper([
        OsStr::new("claude"),
        OsStr::new("rewrite-session-command"),
        path(&settings),
        OsStr::new("--command"),
        OsStr::new("new hook"),
    ]));
    assert_eq!(
        rewritten["hooks"]["SessionStart"][0]["hooks"][0]["command"],
        "new hook"
    );
    assert_eq!(rewritten["discarded"], true);

    let hcom = write_json(
        &directory,
        "hcom.json",
        &json!({
            "permissions": {"allow": ["hcom"]},
            "hooks": {"SessionStart": [{"source": "hcom"}]}
        }),
    );
    let herdr = write_json(
        &directory,
        "herdr.json",
        &json!({"hooks": {"SessionStart": [{"source": "herdr"}]}}),
    );
    let merged = parse_success(helper([
        OsStr::new("claude"),
        OsStr::new("merge-settings"),
        OsStr::new("--herdr"),
        path(&herdr),
        OsStr::new("--base"),
        path(&settings),
        OsStr::new("--hcom"),
        path(&hcom),
    ]));
    assert_eq!(merged["permissions"]["allow"], json!(["base", "hcom"]));
    assert_eq!(
        merged["hooks"]["SessionStart"],
        json!([
            {"source": "hcom"},
            {"hooks": [{"type": "command", "command": "old"}]},
            {"source": "herdr"}
        ])
    );
}

#[test]
fn codex_commands_read_transform_and_emit_compact_json() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("config.toml");
    fs::write(
        &config,
        concat!(
            "[hooks.state.\"/tmp/hooks.json:session_start:0:0\"]\n",
            "trusted_hash = \"sha256:current\"\n",
            "enabled = true\n",
        ),
    )
    .unwrap();

    let extracted = parse_success(helper([
        OsStr::new("codex"),
        OsStr::new("extract-hook-state"),
        path(&config),
    ]));
    assert_eq!(
        extracted,
        json!({
            "session_start": {
                "trusted_hash": "sha256:current",
                "enabled": true
            }
        })
    );

    let state = write_json(&directory, "state.json", &extracted);
    let rekeyed = parse_success(helper([
        OsStr::new("codex"),
        OsStr::new("rekey-hook-state"),
        path(&state),
        OsStr::new("--hooks-path"),
        OsStr::new("/home/me/.codex/hooks.json"),
    ]));
    assert_eq!(
        rekeyed,
        json!({
            "hooks": {
                "state": {
                    "/home/me/.codex/hooks.json:session_start:0:0": {
                        "trusted_hash": "sha256:current",
                        "enabled": true
                    }
                }
            }
        })
    );

    let hooks = write_json(&directory, "hooks.json", &Value::Null);
    let manifest = write_json(
        &directory,
        "hook-manifest.json",
        &json!([{
            "eventName": "sessionStart",
            "handlerType": "command",
            "matcher": null,
            "command": "herdr hook",
            "timeoutSec": 10
        }]),
    );
    let appended = parse_success(helper([
        OsStr::new("codex"),
        OsStr::new("apply-hook-manifest"),
        OsStr::new("--manifest"),
        path(&manifest),
        path(&hooks),
    ]));
    assert_eq!(
        appended,
        json!({
            "hooks": {
                "SessionStart": [{
                    "hooks": [{
                        "command": "herdr hook",
                        "timeout": 10,
                        "type": "command"
                    }]
                }]
            }
        })
    );

    let appended_path = write_json(&directory, "appended-hooks.json", &appended);
    let guarded = parse_success(helper([
        OsStr::new("codex"),
        OsStr::new("append-command-hook"),
        OsStr::new("--event"),
        OsStr::new("PreToolUse"),
        OsStr::new("--matcher"),
        OsStr::new("Bash"),
        OsStr::new("--command"),
        OsStr::new("guard hook"),
        OsStr::new("--timeout"),
        OsStr::new("10"),
        path(&appended_path),
    ]));
    assert_eq!(guarded["hooks"]["PreToolUse"][0]["matcher"], "Bash");
    assert_eq!(
        guarded["hooks"]["PreToolUse"][0]["hooks"][0]["command"],
        "guard hook"
    );

    let base = write_json(
        &directory,
        "base.json",
        &json!({"nested": {"base": true, "replace": "base"}}),
    );
    let hcom = write_json(
        &directory,
        "payload-hcom.json",
        &json!({"nested": {"hcom": true, "replace": "hcom"}}),
    );
    let herdr = write_json(
        &directory,
        "payload-herdr.json",
        &json!({"nested": {"herdr": true, "replace": "herdr"}}),
    );
    let merged = parse_success(helper([
        OsStr::new("codex"),
        OsStr::new("merge-payloads"),
        path(&base),
        path(&hcom),
        path(&herdr),
    ]));
    assert_eq!(
        merged,
        json!({
            "nested": {
                "base": true,
                "hcom": true,
                "herdr": true,
                "replace": "herdr"
            }
        })
    );
}

#[test]
fn malformed_json_diagnostic_does_not_echo_input_contents() {
    let directory = tempfile::tempdir().unwrap();
    let settings = directory.path().join("settings.json");
    fs::write(&settings, "{\"private-token\":\"must-not-leak\",]").unwrap();

    let output = helper([
        OsStr::new("claude"),
        OsStr::new("select-integration"),
        path(&settings),
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("invalid Claude settings JSON"));
    assert!(!stderr.contains("private-token"));
    assert!(!stderr.contains("must-not-leak"));

    let base = write_json(
        &directory,
        "base.json",
        &json!({"hooks": {"SYNTHETIC_SECRET_MARKER": {}}}),
    );
    let hcom = write_json(&directory, "hcom.json", &json!({}));
    let herdr = write_json(&directory, "herdr.json", &json!({}));
    let output = helper([
        OsStr::new("claude"),
        OsStr::new("merge-settings"),
        OsStr::new("--base"),
        path(&base),
        OsStr::new("--hcom"),
        path(&hcom),
        OsStr::new("--herdr"),
        path(&herdr),
    ]);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(stderr.contains("Claude hook event must be an array"));
    assert!(!stderr.contains("SYNTHETIC_SECRET_MARKER"));
}
