use std::path::Path;

use serde::Deserialize;
use serde_json::{Map, Value, json};

use crate::error::{AppError, Result};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HooksListResponse {
    pub data: Vec<HooksListEntry>,
}

#[derive(Debug, Deserialize)]
pub struct HooksListEntry {
    pub hooks: Vec<HookMetadata>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HookMetadata {
    pub key: String,
    pub event_name: String,
    #[serde(default)]
    pub command: Option<String>,
    pub current_hash: String,
}

pub fn build_payload(
    hooks_list: &HooksListResponse,
    hook_command: &str,
    hooks_json_path: &Path,
) -> Result<Value> {
    let matching = hooks_list
        .data
        .iter()
        .flat_map(|entry| &entry.hooks)
        .filter(|hook| {
            hook.event_name == "sessionStart" && hook.command.as_deref() == Some(hook_command)
        })
        .collect::<Vec<_>>();

    if matching.len() != 1 {
        return Err(AppError::new(format!(
            "agent-config-helper: expected exactly one Herdr Codex hook, found {}",
            matching.len()
        )));
    }

    let hook = matching[0];
    let suffix = validated_state_suffix(&hook.key)?;
    let hooks_json_path = hooks_json_path.to_str().ok_or_else(|| {
        AppError::new(format!(
            "agent-config-helper: hooks.json path is not valid UTF-8: {}",
            hooks_json_path.display()
        ))
    })?;
    let state_key = format!("{hooks_json_path}:{suffix}");

    let mut state = Map::new();
    state.insert(
        state_key,
        json!({
            "trusted_hash": hook.current_hash,
            "enabled": true,
        }),
    );
    Ok(json!({
        "hooks": {
            "state": Value::Object(state),
        },
    }))
}

fn validated_state_suffix(key: &str) -> Result<String> {
    let mut parts = key.rsplitn(4, ':');
    let handler = parts.next();
    let group = parts.next();
    let event = parts.next();
    let source = parts.next();

    let valid_decimal =
        |value: &str| !value.is_empty() && value.as_bytes().iter().all(u8::is_ascii_digit);
    match (source, event, group, handler) {
        (Some(source), Some("session_start"), Some(group), Some(handler))
            if !source.is_empty() && valid_decimal(group) && valid_decimal(handler) =>
        {
            Ok(format!("session_start:{group}:{handler}"))
        }
        _ => Err(AppError::new(format!(
            "agent-config-helper: unexpected Codex hook key: {key}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn response(hooks: Vec<HookMetadata>) -> HooksListResponse {
        HooksListResponse {
            data: vec![HooksListEntry { hooks }],
        }
    }

    fn hook(key: &str, command: &str) -> HookMetadata {
        HookMetadata {
            key: key.to_string(),
            event_name: "sessionStart".to_string(),
            command: Some(command.to_string()),
            current_hash: "sha256:from-codex".to_string(),
        }
    }

    #[test]
    fn rekeys_the_hook_and_copies_the_codex_hash() {
        let payload = build_payload(
            &response(vec![hook(
                "/tmp/build-home/.codex/hooks.json:session_start:1:0",
                "herdr",
            )]),
            "herdr",
            Path::new("/home/me/.codex/hooks.json"),
        )
        .unwrap();

        assert_eq!(
            payload,
            json!({
                "hooks": {
                    "state": {
                        "/home/me/.codex/hooks.json:session_start:1:0": {
                            "trusted_hash": "sha256:from-codex",
                            "enabled": true,
                        }
                    }
                }
            })
        );
    }

    #[test]
    fn accepts_colons_in_the_source_identity() {
        assert_eq!(
            validated_state_suffix("plugin:name:path:session_start:10:2").unwrap(),
            "session_start:10:2"
        );
    }

    #[test]
    fn rejects_changed_suffix_shapes() {
        for key in [
            "source:sessionStart:0:0",
            "source:session_start:not-a-number:0",
            "source:session_start:0",
            "source:session_start:0:0:extra",
        ] {
            assert!(validated_state_suffix(key).is_err(), "{key}");
        }
    }

    #[test]
    fn requires_exactly_one_matching_hook_across_all_cwds() {
        let duplicate = HooksListResponse {
            data: vec![
                HooksListEntry {
                    hooks: vec![hook("a:session_start:0:0", "herdr")],
                },
                HooksListEntry {
                    hooks: vec![hook("b:session_start:0:0", "herdr")],
                },
            ],
        };
        assert!(
            build_payload(&duplicate, "herdr", Path::new("/home/me/.codex/hooks.json")).is_err()
        );
        assert!(
            build_payload(
                &response(vec![]),
                "herdr",
                Path::new("/home/me/.codex/hooks.json")
            )
            .is_err()
        );
    }
}
