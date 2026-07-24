use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};

use agent_config_helper::merge::merge;
use serde_json::{Value, json};
use tempfile::TempDir;
use toml_edit::DocumentMut;

struct Fixture {
    directory: TempDir,
    source: PathBuf,
    payload: PathBuf,
    output: PathBuf,
}

impl Fixture {
    fn new(source: Option<&str>, payload: Value) -> Self {
        let directory = tempfile::tempdir().unwrap();
        let source_path = directory.path().join("source.toml");
        if let Some(source) = source {
            fs::write(&source_path, source).unwrap();
        }
        let payload_path = directory.path().join("payload.json");
        fs::write(&payload_path, serde_json::to_vec_pretty(&payload).unwrap()).unwrap();
        let output = directory.path().join("out/output.toml");
        Self {
            directory,
            source: source_path,
            payload: payload_path,
            output,
        }
    }

    fn run(&self) {
        merge(&self.source, &self.payload, &self.output).unwrap();
    }

    fn text(&self) -> String {
        fs::read_to_string(&self.output).unwrap()
    }

    fn document(&self) -> DocumentMut {
        self.text().parse().unwrap()
    }
}

#[test]
fn new_document_gets_mode_0600_and_creates_output_parent() {
    let fixture = Fixture::new(None, json!({"a": {"b": 1}}));
    fixture.run();

    assert_eq!(mode(&fixture.output), 0o600);
    assert_eq!(fixture.document()["a"]["b"].as_integer(), Some(1));
}

#[test]
fn existing_permission_bits_are_replicated() {
    let fixture = Fixture::new(Some("x = 1\n"), json!({"y": 2}));
    if fs::set_permissions(&fixture.source, fs::Permissions::from_mode(0o2640)).is_err() {
        // Nix's Linux sandbox forbids setting setgid. The implementation
        // still preserves all 0o7777 bits when the filesystem permits them.
        fs::set_permissions(&fixture.source, fs::Permissions::from_mode(0o640)).unwrap();
    }
    let source_mode = mode(&fixture.source);
    fixture.run();

    assert_eq!(mode(&fixture.output), source_mode);
}

#[test]
fn source_symlink_is_followed_for_content_and_mode() {
    let fixture = Fixture::new(None, json!({"managed": true}));
    let referent = fixture.directory.path().join("referent.toml");
    fs::write(&referent, "keep = \"yes\"\n").unwrap();
    fs::set_permissions(&referent, fs::Permissions::from_mode(0o640)).unwrap();
    symlink(&referent, &fixture.source).unwrap();

    fixture.run();

    assert!(fixture.text().contains("keep = \"yes\""));
    assert_eq!(mode(&fixture.output), 0o640);
}

#[test]
fn empty_payload_round_trips_complex_unmanaged_format_byte_for_byte() {
    let source = concat!(
        "# leading comment\n",
        "\"quoted:key\" = 'literal' # key tail\n",
        "inline = { keep = true, nested = { value = 1 } } # inline tail\n",
        "array = [ 1, \"two\", { three = 3 } ]\n",
        "when = 1979-05-27T07:32:00Z\n",
        "dotted.keep = 1 # dotted tail\n",
        "\n",
        "# before agents\n",
        "[[agents]]\n",
        "name = \"one\"\n",
        "\n",
        "[[agents]]\n",
        "name = \"two\"\n",
    );
    let fixture = Fixture::new(Some(source), json!({}));
    fixture.run();

    assert_eq!(fixture.text(), source);
}

#[test]
fn deep_merge_preserves_inline_dotted_and_comment_formatting() {
    let source = concat!(
        "# leading\n",
        "\"quoted:key\" = { keep = \"yes\", managed = false } # inline tail\n",
        "dotted.keep = 1 # dotted tail\n",
        "\n",
        "# before table\n",
        "[tool] # table tail\n",
        "keep = \"yes\" # key tail\n",
    );
    let fixture = Fixture::new(
        Some(source),
        json!({
            "quoted:key": {"managed": true, "new": 2},
            "dotted": {"new": 2},
            "tool": {"new": 2}
        }),
    );
    fixture.run();

    let text = fixture.text();
    let document: DocumentMut = text.parse().unwrap();
    assert_eq!(document["quoted:key"]["keep"].as_str(), Some("yes"));
    assert_eq!(document["quoted:key"]["managed"].as_bool(), Some(true));
    assert_eq!(document["dotted"]["keep"].as_integer(), Some(1));
    assert_eq!(document["dotted"]["new"].as_integer(), Some(2));
    assert_eq!(document["tool"]["keep"].as_str(), Some("yes"));
    assert!(text.contains("# leading"));
    assert!(text.contains("# inline tail"));
    assert!(text.contains("dotted.keep = 1 # dotted tail"));
    assert!(text.contains("# before table"));
    assert!(text.contains("[tool] # table tail"));
    assert!(text.contains("keep = \"yes\" # key tail"));
}

#[test]
fn scalar_replacement_preserves_quoted_key_and_trailing_comment() {
    let fixture = Fixture::new(
        Some("\"special:key\" = \"old\" # keep this\n"),
        json!({"special:key": "new"}),
    );
    fixture.run();

    assert_eq!(fixture.text(), "\"special:key\" = \"new\" # keep this\n");
}

#[test]
fn scalar_and_table_replace_each_other_without_touching_siblings() {
    let scalar = Fixture::new(
        Some("keep = 1\nvalue = \"flat\" # removed with value\n"),
        json!({"value": {"nested": true}}),
    );
    scalar.run();
    assert_eq!(scalar.document()["keep"].as_integer(), Some(1));
    assert_eq!(scalar.document()["value"]["nested"].as_bool(), Some(true));

    let table = Fixture::new(
        Some("keep = 1\n\n[value] # removed table\nnested = true\n"),
        json!({"value": "flat"}),
    );
    table.run();
    assert_eq!(table.document()["keep"].as_integer(), Some(1));
    assert_eq!(table.document()["value"].as_str(), Some("flat"));
    assert!(!table.text().contains("nested"));
}

#[test]
fn object_arrays_become_ordered_arrays_of_tables() {
    let fixture = Fixture::new(
        None,
        json!({
            "skills": {
                "config": [
                    {"path": "/first", "enabled": false},
                    {"path": "/second", "enabled": true}
                ]
            }
        }),
    );
    fixture.run();

    let document = fixture.document();
    let skills = document["skills"]["config"].as_array_of_tables().unwrap();
    assert_eq!(skills.len(), 2);
    assert_eq!(skills.get(0).unwrap()["path"].as_str(), Some("/first"));
    assert_eq!(skills.get(1).unwrap()["path"].as_str(), Some("/second"));
}

#[test]
fn exact_deletion_uses_literal_components_and_prunes_only_empty_parents() {
    let source = concat!(
        "[plugins.\"keep@source\"]\n",
        "enabled = true\n",
        "\n",
        "[plugins.\"herdr@herdr\"]\n",
        "enabled = false\n",
        "\n",
        "[permissions.local-dev.network]\n",
        "enabled = true\n",
        "\n",
        "[only.child]\n",
        "leaf = true\n",
    );
    let fixture = Fixture::new(
        Some(source),
        json!({
            "__delete": [
                ["plugins", "herdr@herdr"],
                ["permissions", "local-dev", "network"],
                ["only", "child", "leaf"],
                ["missing", "path"]
            ],
            "plugins": {"new@source": {"enabled": true}}
        }),
    );
    fixture.run();

    let text = fixture.text();
    let document = fixture.document();
    assert!(document["plugins"].get("herdr@herdr").is_none());
    assert!(document["plugins"].get("keep@source").is_some());
    assert!(document["plugins"].get("new@source").is_some());
    assert!(document.get("permissions").is_none());
    assert!(document.get("only").is_none());
    assert!(!text.contains("__delete"));
}

#[test]
fn prefix_deletion_is_literal_direct_and_does_not_prune_target_table() {
    let source = concat!(
        "[hooks.state.\"/home/me/.codex/hooks.json:one\"]\n",
        "enabled = true\n",
        "\n",
        "[hooks.state.\"/home/me/.codex/hooks.json:two\"]\n",
        "enabled = true\n",
        "\n",
        "[hooks.state.\"/tmp/other.json:one\"]\n",
        "enabled = true\n",
        "\n",
        "[hooks.state.nested.\"/home/me/.codex/hooks.json:deep\"]\n",
        "enabled = true\n",
    );
    let fixture = Fixture::new(
        Some(source),
        json!({
            "__delete_prefixes": [{
                "path": ["hooks", "state"],
                "prefix": "/home/me/.codex/hooks.json:"
            }]
        }),
    );
    fixture.run();

    let document = fixture.document();
    let state = document["hooks"]["state"].as_table().unwrap();
    assert!(state.get("/home/me/.codex/hooks.json:one").is_none());
    assert!(state.get("/home/me/.codex/hooks.json:two").is_none());
    assert!(state.get("/tmp/other.json:one").is_some());
    assert!(
        state["nested"]
            .get("/home/me/.codex/hooks.json:deep")
            .is_some()
    );

    let empty = Fixture::new(
        Some(
            "[hooks.state]\n\n[hooks.state.\"/home/me/.codex/hooks.json:only\"]\nenabled = true\n",
        ),
        json!({
            "__delete_prefixes": [{
                "path": ["hooks", "state"],
                "prefix": "/home/me/.codex/hooks.json:"
            }]
        }),
    );
    empty.run();
    assert!(
        empty.document()["hooks"]["state"]
            .as_table()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn nested_controls_are_skipped_during_deep_merge() {
    let fixture = Fixture::new(
        None,
        json!({
            "outer": {
                "__delete": [["keep"]],
                "__delete_prefixes": [{"path": [], "prefix": "k"}],
                "keep": true
            }
        }),
    );
    fixture.run();

    let text = fixture.text();
    assert_eq!(fixture.document()["outer"]["keep"].as_bool(), Some(true));
    assert!(!text.contains("__delete"));
}

#[test]
fn controls_inside_array_of_tables_remain_atomic_payload_data() {
    let fixture = Fixture::new(
        None,
        json!({
            "items": [{
                "__delete": [["direct"]],
                "child": {
                    "__delete": [["nested"]],
                    "keep": true
                }
            }]
        }),
    );
    fixture.run();

    let document = fixture.document();
    let tables = document["items"]
        .as_array_of_tables()
        .unwrap()
        .iter()
        .collect::<Vec<_>>();
    assert!(tables[0].contains_key("__delete"));
    assert!(
        tables[0]["child"]
            .as_table()
            .unwrap()
            .contains_key("__delete")
    );
}

#[test]
fn real_payload_shape_handles_special_keys_arrays_and_controls() {
    let source = concat!(
        "# dynamic project state\n",
        "[projects.\"/repo\"]\n",
        "trust_level = \"trusted\"\n",
        "\n",
        "[plugins.\"herdr@herdr\"]\n",
        "enabled = true\n",
        "\n",
        "[hooks.state.\"/home/me/.codex/hooks.json:old:0:0\"]\n",
        "trusted_hash = \"old\"\n",
    );
    let fixture = Fixture::new(
        Some(source),
        json!({
            "__delete": [["plugins", "herdr@herdr"]],
            "__delete_prefixes": [{
                "path": ["hooks", "state"],
                "prefix": "/home/me/.codex/hooks.json:"
            }],
            "permissions": {
                "local-dev": {
                    "filesystem": {"~/.cache": "write"}
                }
            },
            "plugins": {
                "github@openai-curated": {"enabled": false}
            },
            "skills": {
                "config": [
                    {"path": "/home/me/.codex/skills/one/SKILL.md", "enabled": false},
                    {"path": "/home/me/.codex/skills/two/SKILL.md", "enabled": true}
                ]
            },
            "tui": {"status_line": ["model", "git-branch"]},
            "hooks": {
                "state": {
                    "/home/me/.codex/hooks.json:session_start:1:0": {
                        "trusted_hash": "sha256:new",
                        "enabled": true
                    }
                }
            }
        }),
    );
    fixture.run();

    let document = fixture.document();
    assert_eq!(
        document["projects"]["/repo"]["trust_level"].as_str(),
        Some("trusted")
    );
    assert!(document["plugins"].get("herdr@herdr").is_none());
    assert_eq!(
        document["permissions"]["local-dev"]["filesystem"]["~/.cache"].as_str(),
        Some("write")
    );
    assert_eq!(
        document["hooks"]["state"]["/home/me/.codex/hooks.json:session_start:1:0"]["trusted_hash"]
            .as_str(),
        Some("sha256:new")
    );
    assert_eq!(
        document["skills"]["config"]
            .as_array_of_tables()
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn applying_the_same_payload_twice_is_byte_idempotent() {
    let source = "\"inline:key\" = { keep = true, managed = false } # tail\n";
    let payload = json!({
        "inline:key": {"managed": true, "new": 2},
        "skills": {"config": [{"path": "/one", "enabled": false}]}
    });
    let first = Fixture::new(Some(source), payload.clone());
    first.run();
    let first_text = first.text();

    let second = Fixture::new(Some(&first_text), payload);
    second.run();

    assert_eq!(second.text(), first_text);
}

#[test]
fn malformed_toml_error_does_not_echo_source_values_or_modify_source() {
    let secret = "SECRET_PROJECT_TRUST_VALUE";
    let source = format!("project = \"{secret}\"\nbroken = [\n");
    let fixture = Fixture::new(Some(&source), json!({}));

    let error = merge(&fixture.source, &fixture.payload, &fixture.output)
        .unwrap_err()
        .to_string();

    assert!(error.contains("invalid TOML"));
    assert!(!error.contains(secret));
    assert_eq!(fs::read_to_string(&fixture.source).unwrap(), source);
    assert!(!fixture.output.exists());
}

#[test]
fn output_creation_failure_does_not_modify_source() {
    let source = "keep = true\n";
    let mut fixture = Fixture::new(Some(source), json!({"managed": true}));
    let non_directory = fixture.directory.path().join("not-a-directory");
    fs::write(&non_directory, "block output creation").unwrap();
    fixture.output = non_directory.join("output.toml");

    assert!(merge(&fixture.source, &fixture.payload, &fixture.output).is_err());
    assert_eq!(fs::read_to_string(&fixture.source).unwrap(), source);
}

#[test]
fn invalid_json_controls_and_values_fail_before_output_without_echoing_values() {
    let source = "keep = true\n";
    for payload in [
        "{\"secret\":\"SECRET_JSON_VALUE\"",
        r#"{"__delete":"SECRET_CONTROL_VALUE"}"#,
        r#"{"value":null}"#,
        r#"{"value":9223372036854775808}"#,
        r#"{"value":-9223372036854775809}"#,
        r#"{"value":18446744073709551616}"#,
        r#"{"__delete":[[]]}"#,
        r#"{"__delete_prefixes":[{"path":[],"prefix":"x","extra":true}]}"#,
    ] {
        let fixture = Fixture::new(Some(source), json!({}));
        fs::write(&fixture.payload, payload).unwrap();

        let error = merge(&fixture.source, &fixture.payload, &fixture.output)
            .unwrap_err()
            .to_string();

        assert!(!error.contains("SECRET_JSON_VALUE"));
        assert!(!error.contains("SECRET_CONTROL_VALUE"));
        assert_eq!(fs::read_to_string(&fixture.source).unwrap(), source);
        assert!(!fixture.output.exists());
    }
}

fn mode(path: &Path) -> u32 {
    fs::metadata(path).unwrap().permissions().mode() & 0o7777
}
