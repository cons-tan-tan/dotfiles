use std::collections::BTreeSet;

use serde_json::{Map, Number, Value};
use toml_edit::{DocumentMut, Item, Value as TomlValue};

use crate::error::{AppError, Result};

pub fn claude_select_integration(settings: &Value) -> Result<Value> {
    let source = match settings {
        Value::Object(source) => Some(source),
        Value::Null => None,
        _ => {
            return Err(shape_error(
                "Claude integration settings must be an object or null",
            ));
        }
    };
    let mut selected = Map::new();
    for key in ["hooks", "env", "permissions"] {
        selected.insert(
            key.to_owned(),
            source
                .and_then(|object| object.get(key))
                .cloned()
                .unwrap_or(Value::Null),
        );
    }
    Ok(Value::Object(selected))
}

pub fn claude_rewrite_session_command(settings: &Value, command: &str) -> Result<Value> {
    let mut output = object_clone(settings, "Claude settings")?;
    let hooks = object_field_mut(&mut output, "hooks", "Claude settings hooks")?;
    let session_start = hooks
        .get_mut("SessionStart")
        .ok_or_else(|| shape_error("Claude SessionStart hooks are required"))?;
    let groups = session_start
        .as_array_mut()
        .ok_or_else(|| shape_error("Claude SessionStart hooks must be an array"))?;

    for group in groups {
        let group = group
            .as_object_mut()
            .ok_or_else(|| shape_error("Claude SessionStart hook group must be an object"))?;
        let inner = group
            .get_mut("hooks")
            .and_then(Value::as_array_mut)
            .ok_or_else(|| shape_error("Claude SessionStart hook group hooks must be an array"))?;
        for hook in inner {
            let hook = hook
                .as_object_mut()
                .ok_or_else(|| shape_error("Claude SessionStart hook must be an object"))?;
            hook.insert("command".to_owned(), Value::String(command.to_owned()));
        }
    }

    Ok(Value::Object(output))
}

pub fn claude_merge_settings(base: &Value, hcom: &Value, herdr: &Value) -> Result<Value> {
    let mut output = object_clone(base, "Claude base settings")?;
    let hcom = object_ref(hcom, "Claude hcom settings")?;
    let herdr = object_ref(herdr, "Claude Herdr settings")?;

    let base_allow = nested_optional_array(&output, "permissions", "allow")?;
    let hcom_allow = nested_optional_array(hcom, "permissions", "allow")?;
    let merged_allow = match (base_allow, hcom_allow) {
        (None, None) => Value::Null,
        (Some(base), None) => Value::Array(base.to_vec()),
        (None, Some(hcom)) => Value::Array(hcom.to_vec()),
        (Some(base), Some(hcom)) => {
            let mut values = base.to_vec();
            values.extend_from_slice(hcom);
            Value::Array(values)
        }
    };
    let permissions = object_field_or_default(&mut output, "permissions", "Claude permissions")?;
    permissions.insert("allow".to_owned(), merged_allow);

    let base_hooks = optional_hook_map(output.get("hooks"), "Claude base hooks")?;
    let hcom_hooks = optional_hook_map(hcom.get("hooks"), "Claude hcom hooks")?;
    let herdr_hooks = optional_hook_map(herdr.get("hooks"), "Claude Herdr hooks")?;
    let mut event_names = BTreeSet::new();
    event_names.extend(base_hooks.keys().cloned());
    event_names.extend(hcom_hooks.keys().cloned());
    event_names.extend(herdr_hooks.keys().cloned());

    let mut merged_hooks = Map::new();
    for event in event_names {
        let mut entries = Vec::new();
        entries.extend(optional_event_array(hcom_hooks.get(&event))?);
        entries.extend(optional_event_array(base_hooks.get(&event))?);
        entries.extend(optional_event_array(herdr_hooks.get(&event))?);
        merged_hooks.insert(event, Value::Array(entries));
    }
    output.insert("hooks".to_owned(), Value::Object(merged_hooks));

    Ok(Value::Object(output))
}

pub fn codex_extract_hook_state_from_toml(source: &str) -> Result<Value> {
    let document = source
        .parse::<DocumentMut>()
        .map_err(|_| shape_error("Codex config TOML is invalid"))?;
    let hooks = document
        .get("hooks")
        .and_then(Item::as_table_like)
        .ok_or_else(|| shape_error("Codex config hooks must be a table"))?;
    let state = hooks
        .get("state")
        .and_then(Item::as_table_like)
        .ok_or_else(|| shape_error("Codex config hooks.state must be a table"))?;

    let mut extracted = Map::new();
    for (key, value) in state.iter() {
        let event = key
            .rsplit(':')
            .nth(2)
            .ok_or_else(|| shape_error("Codex hook state key must contain at least two colons"))?;
        extracted.insert(event.to_owned(), toml_item_to_json(value)?);
    }
    Ok(Value::Object(extracted))
}

pub fn codex_rekey_hook_state(state: &Value, hooks_path: &str) -> Result<Value> {
    let state = object_ref(state, "Codex hook state")?;
    let mut rekeyed = Map::new();
    for (event, value) in state {
        rekeyed.insert(format!("{hooks_path}:{event}:0:0"), value.clone());
    }
    let mut state_wrapper = Map::new();
    state_wrapper.insert("state".to_owned(), Value::Object(rekeyed));
    let mut hooks_wrapper = Map::new();
    hooks_wrapper.insert("hooks".to_owned(), Value::Object(state_wrapper));
    Ok(Value::Object(hooks_wrapper))
}

pub fn codex_append_session_hook(hooks: &Value, command: &str) -> Result<Value> {
    let mut output = match hooks {
        Value::Object(output) => output.clone(),
        Value::Null => Map::new(),
        _ => return Err(shape_error("Codex hooks must be an object or null")),
    };
    let hooks = object_field_or_default(&mut output, "hooks", "Codex hooks table")?;
    let mut session_start = match hooks.get("SessionStart") {
        None | Some(Value::Null) | Some(Value::Bool(false)) => Vec::new(),
        Some(Value::Array(entries)) => entries.clone(),
        Some(_) => return Err(shape_error("Codex SessionStart hooks must be an array")),
    };

    let mut command_hook = Map::new();
    command_hook.insert("command".to_owned(), Value::String(command.to_owned()));
    command_hook.insert("timeout".to_owned(), Value::Number(Number::from(10)));
    command_hook.insert("type".to_owned(), Value::String("command".to_owned()));
    let mut group = Map::new();
    group.insert(
        "hooks".to_owned(),
        Value::Array(vec![Value::Object(command_hook)]),
    );
    session_start.push(Value::Object(group));
    hooks.insert("SessionStart".to_owned(), Value::Array(session_start));

    Ok(Value::Object(output))
}

pub fn codex_merge_payloads(base: &Value, hcom: &Value, herdr: &Value) -> Result<Value> {
    let mut output = object_clone(base, "Codex base payload")?;
    recursive_merge(&mut output, object_ref(hcom, "Codex hcom payload")?);
    recursive_merge(&mut output, object_ref(herdr, "Codex Herdr payload")?);
    Ok(Value::Object(output))
}

fn object_ref<'a>(value: &'a Value, name: &str) -> Result<&'a Map<String, Value>> {
    value
        .as_object()
        .ok_or_else(|| shape_error(format!("{name} must be an object")))
}

fn object_clone(value: &Value, name: &str) -> Result<Map<String, Value>> {
    object_ref(value, name).cloned()
}

fn object_field_mut<'a>(
    object: &'a mut Map<String, Value>,
    key: &str,
    name: &str,
) -> Result<&'a mut Map<String, Value>> {
    object
        .get_mut(key)
        .and_then(Value::as_object_mut)
        .ok_or_else(|| shape_error(format!("{name} must be an object")))
}

fn object_field_or_default<'a>(
    object: &'a mut Map<String, Value>,
    key: &str,
    name: &str,
) -> Result<&'a mut Map<String, Value>> {
    let value = object
        .entry(key.to_owned())
        .or_insert_with(|| Value::Object(Map::new()));
    if value.is_null() {
        *value = Value::Object(Map::new());
    }
    value
        .as_object_mut()
        .ok_or_else(|| shape_error(format!("{name} must be an object or null")))
}

fn nested_optional_array<'a>(
    object: &'a Map<String, Value>,
    parent: &str,
    child: &str,
) -> Result<Option<&'a [Value]>> {
    let Some(parent) = object.get(parent) else {
        return Ok(None);
    };
    if parent.is_null() {
        return Ok(None);
    }
    let parent = parent
        .as_object()
        .ok_or_else(|| shape_error("Claude permissions must be an object or null"))?;
    match parent.get(child) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::Array(values)) => Ok(Some(values)),
        Some(_) => Err(shape_error(
            "Claude permissions.allow must be an array or null",
        )),
    }
}

fn optional_hook_map<'a>(value: Option<&'a Value>, name: &str) -> Result<&'a Map<String, Value>> {
    static EMPTY: std::sync::LazyLock<Map<String, Value>> = std::sync::LazyLock::new(Map::new);
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => Ok(&EMPTY),
        Some(Value::Object(hooks)) => Ok(hooks),
        Some(_) => Err(shape_error(format!(
            "{name} must be an object, false, or null"
        ))),
    }
}

fn optional_event_array(value: Option<&Value>) -> Result<Vec<Value>> {
    match value {
        None | Some(Value::Null) | Some(Value::Bool(false)) => Ok(Vec::new()),
        Some(Value::Array(entries)) => Ok(entries.clone()),
        Some(_) => Err(shape_error(
            "Claude hook event must be an array, false, or null",
        )),
    }
}

fn recursive_merge(destination: &mut Map<String, Value>, source: &Map<String, Value>) {
    for (key, source_value) in source {
        match (destination.get_mut(key), source_value) {
            (Some(Value::Object(destination)), Value::Object(source)) => {
                recursive_merge(destination, source);
            }
            (Some(destination), source) => *destination = source.clone(),
            (None, source) => {
                destination.insert(key.clone(), source.clone());
            }
        }
    }
}

fn toml_item_to_json(item: &Item) -> Result<Value> {
    match item {
        Item::None => Err(shape_error("Codex hook state contains an empty TOML item")),
        Item::Value(value) => toml_value_to_json(value),
        Item::Table(table) => {
            let mut object = Map::new();
            for (key, value) in table.iter() {
                object.insert(key.to_owned(), toml_item_to_json(value)?);
            }
            Ok(Value::Object(object))
        }
        Item::ArrayOfTables(tables) => {
            let mut values = Vec::new();
            for table in tables.iter() {
                let mut object = Map::new();
                for (key, value) in table.iter() {
                    object.insert(key.to_owned(), toml_item_to_json(value)?);
                }
                values.push(Value::Object(object));
            }
            Ok(Value::Array(values))
        }
    }
}

fn toml_value_to_json(value: &TomlValue) -> Result<Value> {
    match value {
        TomlValue::String(value) => Ok(Value::String(value.value().clone())),
        TomlValue::Integer(value) => Ok(Value::Number(Number::from(*value.value()))),
        TomlValue::Float(value) => {
            let value = *value.value();
            if value.is_nan() {
                Ok(Value::String("NaN".to_owned()))
            } else if value == f64::INFINITY {
                Ok(Value::String("Infinity".to_owned()))
            } else if value == f64::NEG_INFINITY {
                Ok(Value::String("-Infinity".to_owned()))
            } else {
                Number::from_f64(value)
                    .map(Value::Number)
                    .ok_or_else(|| shape_error("Codex hook state contains an invalid float"))
            }
        }
        TomlValue::Boolean(value) => Ok(Value::Bool(*value.value())),
        TomlValue::Datetime(value) => {
            let datetime = value.value();
            let rendered = match (datetime.date, datetime.time, datetime.offset) {
                (Some(date), None, None) => format!("{date}T00:00:00Z"),
                (None, Some(time), None) => format!("0000-01-01T{time}Z"),
                (Some(_), Some(_), None) => format!("{datetime}Z"),
                _ => datetime.to_string(),
            };
            Ok(Value::String(rendered))
        }
        TomlValue::Array(values) => values
            .iter()
            .map(toml_value_to_json)
            .collect::<Result<Vec<_>>>()
            .map(Value::Array),
        TomlValue::InlineTable(table) => {
            let mut object = Map::new();
            for (key, value) in table.iter() {
                object.insert(key.to_owned(), toml_value_to_json(value)?);
            }
            Ok(Value::Object(object))
        }
    }
}

fn shape_error(message: impl Into<String>) -> AppError {
    AppError::new(format!(
        "agent-config-helper: invalid agent configuration shape: {}",
        message.into()
    ))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn selects_only_claude_integration_fields_and_defaults_missing_to_null() {
        let selected = claude_select_integration(&json!({
            "hooks": {"SessionStart": []},
            "env": {"HCOM": "1"},
            "unknown": "discarded"
        }))
        .unwrap();

        assert_eq!(
            selected,
            json!({
                "hooks": {"SessionStart": []},
                "env": {"HCOM": "1"},
                "permissions": null
            })
        );
        assert_eq!(
            claude_select_integration(&Value::Null).unwrap(),
            json!({"hooks": null, "env": null, "permissions": null})
        );
    }

    #[test]
    fn rewrites_every_claude_session_hook_and_preserves_unknown_fields() {
        let input = json!({
            "hooks": {
                "SessionStart": [{
                    "matcher": "*",
                    "hooks": [
                        {"type": "command", "command": "old", "timeout": 5},
                        {"type": "prompt", "prompt": "keep"}
                    ]
                }]
            },
            "unknown": true
        });
        let output = claude_rewrite_session_command(&input, "new").unwrap();

        assert_eq!(output["unknown"], true);
        assert_eq!(
            output["hooks"]["SessionStart"][0]["hooks"][0]["command"],
            "new"
        );
        assert_eq!(
            output["hooks"]["SessionStart"][0]["hooks"][1]["command"],
            "new"
        );
        assert_eq!(
            output["hooks"]["SessionStart"][0]["hooks"][1]["prompt"],
            "keep"
        );
    }

    #[test]
    fn merges_claude_permissions_and_hooks_in_the_existing_order() {
        let output = claude_merge_settings(
            &json!({
                "permissions": {"allow": ["base", "duplicate"]},
                "hooks": {
                    "Zed": [{"source": "base-z"}],
                    "Alpha": [{"source": "base-a"}]
                },
                "base_unknown": true
            }),
            &json!({
                "permissions": {"allow": ["hcom", "duplicate"]},
                "hooks": {"Alpha": [{"source": "hcom"}]},
                "env": {"discarded": true}
            }),
            &json!({
                "hooks": {
                    "Alpha": [{"source": "herdr"}],
                    "Beta": [{"source": "herdr-b"}]
                },
                "discarded": true
            }),
        )
        .unwrap();

        assert_eq!(
            output["permissions"]["allow"],
            json!(["base", "duplicate", "hcom", "duplicate"])
        );
        assert_eq!(
            output["hooks"]["Alpha"],
            json!([
                {"source": "hcom"},
                {"source": "base-a"},
                {"source": "herdr"}
            ])
        );
        assert_eq!(
            output["hooks"]
                .as_object()
                .unwrap()
                .keys()
                .collect::<Vec<_>>(),
            vec!["Alpha", "Beta", "Zed"]
        );
        assert_eq!(output["base_unknown"], true);
        assert!(output.get("env").is_none());
        assert!(output.get("discarded").is_none());
    }

    #[test]
    fn extracts_codex_state_with_last_value_and_first_key_position() {
        let output = codex_extract_hook_state_from_toml(
            r#"
[hooks.state."/sandbox/hooks.json:SessionStart:0:0"]
trusted_hash = "first"
enabled = true
unknown = { nested = [1, 2] }
date = 2026-07-24
time = 12:34:56
positive_infinity = inf
not_a_number = nan

[hooks.state."/other/hooks.json:Notification:0:0"]
trusted_hash = "middle"

[hooks.state."/real/hooks.json:SessionStart:1:1"]
trusted_hash = "last"
"#,
        )
        .unwrap();

        assert_eq!(
            output.as_object().unwrap().keys().collect::<Vec<_>>(),
            vec!["SessionStart", "Notification"]
        );
        assert_eq!(output["SessionStart"]["trusted_hash"], "last");
        assert_eq!(output["SessionStart"]["enabled"], Value::Null);
        assert_eq!(output["Notification"]["trusted_hash"], "middle");
    }

    #[test]
    fn converts_yj_special_toml_scalars_compatibly() {
        let output = codex_extract_hook_state_from_toml(
            r#"
[hooks.state."/sandbox/hooks.json:SessionStart:0:0"]
date = 2026-07-24
time = 12:34:56
local_datetime = 2026-07-24T12:34:56
offset_datetime = 2026-07-24T12:34:56+09:00
positive_infinity = inf
negative_infinity = -inf
not_a_number = nan
"#,
        )
        .unwrap();

        assert_eq!(output["SessionStart"]["date"], "2026-07-24T00:00:00Z");
        assert_eq!(output["SessionStart"]["time"], "0000-01-01T12:34:56Z");
        assert_eq!(
            output["SessionStart"]["local_datetime"],
            "2026-07-24T12:34:56Z"
        );
        assert_eq!(
            output["SessionStart"]["offset_datetime"],
            "2026-07-24T12:34:56+09:00"
        );
        assert_eq!(output["SessionStart"]["positive_infinity"], "Infinity");
        assert_eq!(output["SessionStart"]["negative_infinity"], "-Infinity");
        assert_eq!(output["SessionStart"]["not_a_number"], "NaN");
    }

    #[test]
    fn rekeys_state_and_appends_the_codex_session_hook() {
        let rekeyed = codex_rekey_hook_state(
            &json!({
                "SessionStart": {"trusted_hash": "opaque"},
                "Notification": {"enabled": false}
            }),
            "/home/me/.codex/hooks.json",
        )
        .unwrap();
        assert_eq!(
            rekeyed["hooks"]["state"]["/home/me/.codex/hooks.json:SessionStart:0:0"]["trusted_hash"],
            "opaque"
        );

        let appended = codex_append_session_hook(
            &json!({"hooks": {"SessionStart": false}, "unknown": true}),
            "run hook",
        )
        .unwrap();
        assert_eq!(appended["unknown"], true);
        assert_eq!(
            appended["hooks"]["SessionStart"][0],
            json!({
                "hooks": [{
                    "command": "run hook",
                    "timeout": 10,
                    "type": "command"
                }]
            })
        );
    }

    #[test]
    fn recursively_merges_codex_payloads_and_keeps_controls_opaque() {
        let output = codex_merge_payloads(
            &json!({
                "hooks": {"state": {"base": 1}},
                "array": [1],
                "__delete": [["base"]]
            }),
            &json!({
                "hooks": {"state": {"hcom": 2}},
                "array": [2],
                "__delete_prefixes": [{"path": ["hooks"], "prefix": "old"}]
            }),
            &json!({
                "hooks": {"state": {"base": 3, "herdr": 4}},
                "__delete": [["herdr"]]
            }),
        )
        .unwrap();

        assert_eq!(
            output["hooks"]["state"],
            json!({"base": 3, "hcom": 2, "herdr": 4})
        );
        assert_eq!(output["array"], json!([2]));
        assert_eq!(output["__delete"], json!([["herdr"]]));
        assert_eq!(output["__delete_prefixes"][0]["prefix"], "old");
    }

    #[test]
    fn rejects_malformed_domain_shapes_without_echoing_values() {
        let secret = "SYNTHETIC_SECRET_MARKER";
        let errors = [
            claude_rewrite_session_command(&json!({"hooks": {}}), secret).unwrap_err(),
            claude_merge_settings(
                &json!({}),
                &json!({"hooks": {"SYNTHETIC_SECRET_MARKER": {}}}),
                &json!({}),
            )
            .unwrap_err(),
            codex_extract_hook_state_from_toml("[hooks]\nstate = 1").unwrap_err(),
            codex_rekey_hook_state(&json!([]), secret).unwrap_err(),
            codex_append_session_hook(&json!({"hooks": {"SessionStart": {}}}), secret).unwrap_err(),
            codex_merge_payloads(&json!({}), &json!([]), &json!({})).unwrap_err(),
        ];
        for error in errors {
            assert!(!error.to_string().contains(secret));
        }
    }
}
