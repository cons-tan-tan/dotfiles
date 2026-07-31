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

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HookMetadata {
    pub key: String,
    pub event_name: String,
    #[serde(default)]
    pub handler_type: Option<String>,
    #[serde(default)]
    pub matcher: Option<String>,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub timeout_sec: Option<u64>,
    #[serde(default)]
    pub enabled: Option<bool>,
    pub current_hash: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct HookSpec {
    pub event_name: String,
    pub handler_type: String,
    pub matcher: Option<String>,
    pub command: String,
    pub timeout_sec: u64,
}

pub fn build_payload_for_specs(
    hooks_list: &HooksListResponse,
    specs: &[HookSpec],
    hooks_json_path: &Path,
) -> Result<Value> {
    validate_specs(specs)?;
    let hooks_json_path = hooks_json_path.to_str().ok_or_else(|| {
        AppError::new(format!(
            "agent-config-helper: hooks.json path is not valid UTF-8: {}",
            hooks_json_path.display()
        ))
    })?;
    let mut state = Map::new();
    for spec in specs {
        let matching = hooks_list
            .data
            .iter()
            .flat_map(|entry| &entry.hooks)
            .filter(|hook| metadata_matches(hook, spec))
            .collect::<Vec<_>>();
        if matching.len() != 1 {
            return Err(AppError::new(format!(
                "agent-config-helper: expected exactly one {} hook from the managed manifest, found {}",
                spec.event_name,
                matching.len()
            )));
        }
        let hook = matching[0];
        let state_event = state_event_name(&spec.event_name)?;
        let suffix = validated_state_suffix_for_event(&hook.key, state_event)?;
        state.insert(
            format!("{hooks_json_path}:{suffix}"),
            json!({
                "trusted_hash": hook.current_hash,
                "enabled": true,
            }),
        );
    }
    if state.len() != specs.len() {
        return Err(AppError::new(
            "agent-config-helper: managed hook manifest produced duplicate trust-state keys",
        ));
    }
    Ok(json!({"hooks": {"state": Value::Object(state)}}))
}

fn metadata_matches(hook: &HookMetadata, spec: &HookSpec) -> bool {
    hook.event_name == spec.event_name
        && hook.handler_type.as_deref() == Some(spec.handler_type.as_str())
        && hook.matcher == spec.matcher
        && hook.command.as_deref() == Some(spec.command.as_str())
        && hook.timeout_sec == Some(spec.timeout_sec)
        && hook.enabled == Some(true)
        && !hook.current_hash.trim().is_empty()
}

pub fn validate_specs(specs: &[HookSpec]) -> Result<()> {
    if specs.is_empty() {
        return Err(AppError::new(
            "agent-config-helper: hook manifest must not be empty",
        ));
    }
    for spec in specs {
        validate_spec(spec)?;
    }
    Ok(())
}

fn validate_spec(spec: &HookSpec) -> Result<()> {
    state_event_name(&spec.event_name)?;
    if spec.handler_type != "command" || spec.command.trim().is_empty() || spec.timeout_sec == 0 {
        return Err(AppError::new(format!(
            "agent-config-helper: invalid managed {} hook manifest entry",
            spec.event_name
        )));
    }
    Ok(())
}

pub fn hooks_event_name(event_name: &str) -> Result<&'static str> {
    match event_name {
        "sessionStart" => Ok("SessionStart"),
        "preToolUse" => Ok("PreToolUse"),
        _ => Err(AppError::new(format!(
            "agent-config-helper: unsupported managed hook event: {event_name}"
        ))),
    }
}

fn state_event_name(event_name: &str) -> Result<&'static str> {
    match event_name {
        "sessionStart" => Ok("session_start"),
        "preToolUse" => Ok("pre_tool_use"),
        _ => Err(AppError::new(format!(
            "agent-config-helper: unsupported managed hook event: {event_name}"
        ))),
    }
}

fn validated_state_suffix_for_event(key: &str, expected_event: &str) -> Result<String> {
    let mut parts = key.rsplitn(4, ':');
    let handler = parts.next();
    let group = parts.next();
    let event = parts.next();
    let source = parts.next();

    let valid_decimal =
        |value: &str| !value.is_empty() && value.as_bytes().iter().all(u8::is_ascii_digit);
    match (source, event, group, handler) {
        (Some(source), Some(event), Some(group), Some(handler))
            if !source.is_empty()
                && event == expected_event
                && valid_decimal(group)
                && valid_decimal(handler) =>
        {
            Ok(format!("{expected_event}:{group}:{handler}"))
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
            handler_type: Some("command".to_string()),
            matcher: None,
            command: Some(command.to_string()),
            timeout_sec: Some(10),
            enabled: Some(true),
            current_hash: "sha256:from-codex".to_string(),
        }
    }

    #[test]
    fn verifies_every_manifest_identity_field_and_event_spelling() {
        let mut session = hook("source:session_start:0:0", "herdr");
        let mut pre_tool = hook("source:pre_tool_use:1:0", "guard");
        pre_tool.event_name = "preToolUse".to_string();
        pre_tool.matcher = Some("Bash".to_string());
        let specs = vec![
            HookSpec {
                event_name: "sessionStart".to_string(),
                handler_type: "command".to_string(),
                matcher: None,
                command: "herdr".to_string(),
                timeout_sec: 10,
            },
            HookSpec {
                event_name: "preToolUse".to_string(),
                handler_type: "command".to_string(),
                matcher: Some("Bash".to_string()),
                command: "guard".to_string(),
                timeout_sec: 10,
            },
        ];
        let payload = build_payload_for_specs(
            &response(vec![session.clone(), pre_tool.clone()]),
            &specs,
            Path::new("/home/me/.codex/hooks.json"),
        )
        .unwrap();
        assert_eq!(payload["hooks"]["state"].as_object().unwrap().len(), 2);
        assert_eq!(
            payload["hooks"]["state"]["/home/me/.codex/hooks.json:session_start:0:0"]["trusted_hash"],
            "sha256:from-codex"
        );
        assert_eq!(
            validated_state_suffix_for_event(
                "plugin:name:path:session_start:10:2",
                "session_start"
            )
            .unwrap(),
            "session_start:10:2"
        );

        session.timeout_sec = Some(11);
        assert!(
            build_payload_for_specs(
                &response(vec![session, pre_tool.clone()]),
                &specs,
                Path::new("/home/me/.codex/hooks.json")
            )
            .is_err()
        );
        pre_tool.matcher = None;
        assert!(
            build_payload_for_specs(
                &response(vec![hook("source:session_start:0:0", "herdr"), pre_tool]),
                &specs,
                Path::new("/home/me/.codex/hooks.json")
            )
            .is_err()
        );

        let mut empty_hash = hook("source:session_start:0:0", "herdr");
        empty_hash.current_hash.clear();
        assert!(
            build_payload_for_specs(
                &response(vec![empty_hash]),
                &specs[..1],
                Path::new("/home/me/.codex/hooks.json")
            )
            .is_err()
        );
    }
}
