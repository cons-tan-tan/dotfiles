use std::path::Path;

use serde_json::{Map, Value};

use crate::error::{AppError, Result};

pub const DELETE_CONTROL: &str = "__delete";
pub const DELETE_PREFIXES_CONTROL: &str = "__delete_prefixes";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DeletePrefix {
    pub path: Vec<String>,
    pub prefix: String,
}

#[derive(Clone, Debug)]
pub struct MergePayload {
    pub delete_paths: Vec<Vec<String>>,
    pub delete_prefixes: Vec<DeletePrefix>,
    pub values: Map<String, Value>,
}

pub fn parse(bytes: &[u8], path: &Path) -> Result<MergePayload> {
    let value: Value = serde_json::from_slice(bytes).map_err(|error| {
        AppError::new(format!(
            "agent-config-helper: invalid JSON in {} at line {}, column {}",
            path.display(),
            error.line(),
            error.column()
        ))
    })?;
    let mut root = value.as_object().cloned().ok_or_else(|| {
        AppError::new(format!(
            "agent-config-helper: merge payload in {} must be a JSON object",
            path.display()
        ))
    })?;

    let delete_paths = match root.remove(DELETE_CONTROL) {
        Some(value) => parse_delete_paths(&value, path)?,
        None => Vec::new(),
    };
    let delete_prefixes = match root.remove(DELETE_PREFIXES_CONTROL) {
        Some(value) => parse_delete_prefixes(&value, path)?,
        None => Vec::new(),
    };
    validate_merge_object(&root, path)?;

    Ok(MergePayload {
        delete_paths,
        delete_prefixes,
        values: root,
    })
}

fn parse_delete_paths(value: &Value, payload_path: &Path) -> Result<Vec<Vec<String>>> {
    let entries = value.as_array().ok_or_else(|| {
        invalid_control(
            payload_path,
            DELETE_CONTROL,
            "must be an array of non-empty string paths",
        )
    })?;
    entries
        .iter()
        .enumerate()
        .map(|(index, entry)| parse_path(entry, payload_path, DELETE_CONTROL, index, false))
        .collect()
}

fn parse_delete_prefixes(value: &Value, payload_path: &Path) -> Result<Vec<DeletePrefix>> {
    let entries = value.as_array().ok_or_else(|| {
        invalid_control(
            payload_path,
            DELETE_PREFIXES_CONTROL,
            "must be an array of objects",
        )
    })?;
    entries
        .iter()
        .enumerate()
        .map(|(index, entry)| {
            let object = entry.as_object().ok_or_else(|| {
                invalid_control_entry(
                    payload_path,
                    DELETE_PREFIXES_CONTROL,
                    index,
                    "must be an object with only path and prefix",
                )
            })?;
            if object.len() != 2 || !object.contains_key("path") || !object.contains_key("prefix") {
                return Err(invalid_control_entry(
                    payload_path,
                    DELETE_PREFIXES_CONTROL,
                    index,
                    "must contain only path and prefix",
                ));
            }
            let path = parse_path(
                object.get("path").expect("path presence checked"),
                payload_path,
                DELETE_PREFIXES_CONTROL,
                index,
                true,
            )?;
            let prefix = object
                .get("prefix")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    invalid_control_entry(
                        payload_path,
                        DELETE_PREFIXES_CONTROL,
                        index,
                        "prefix must be a string",
                    )
                })?
                .to_owned();
            Ok(DeletePrefix { path, prefix })
        })
        .collect()
}

fn parse_path(
    value: &Value,
    payload_path: &Path,
    control: &str,
    index: usize,
    allow_root: bool,
) -> Result<Vec<String>> {
    let components = value.as_array().ok_or_else(|| {
        invalid_control_entry(
            payload_path,
            control,
            index,
            "path must be an array of strings",
        )
    })?;
    if components.is_empty() && !allow_root {
        return Err(invalid_control_entry(
            payload_path,
            control,
            index,
            "path must not be empty",
        ));
    }
    components
        .iter()
        .enumerate()
        .map(|(component_index, component)| {
            component
                .as_str()
                .filter(|component| !component.is_empty())
                .map(str::to_owned)
                .ok_or_else(|| {
                    invalid_control_entry(
                        payload_path,
                        control,
                        index,
                        &format!("path component {component_index} must be a non-empty string"),
                    )
                })
        })
        .collect()
}

fn validate_merge_object(object: &Map<String, Value>, payload_path: &Path) -> Result<()> {
    for (key, value) in object {
        if is_control_key(key) {
            continue;
        }
        match value {
            Value::Object(child) => validate_merge_object(child, payload_path)?,
            value => validate_toml_value(value, payload_path)?,
        }
    }
    Ok(())
}

fn validate_toml_value(value: &Value, payload_path: &Path) -> Result<()> {
    match value {
        Value::Null => Err(AppError::new(format!(
            "agent-config-helper: merge payload in {} contains a value that TOML cannot represent",
            payload_path.display()
        ))),
        Value::Number(number) => {
            let representation = number.to_string();
            let is_float = representation
                .as_bytes()
                .iter()
                .any(|byte| matches!(byte, b'.' | b'e' | b'E'));
            if (is_float && number.as_f64().is_some()) || (!is_float && number.as_i64().is_some()) {
                Ok(())
            } else {
                Err(AppError::new(format!(
                    "agent-config-helper: merge payload in {} contains an integer outside the TOML range",
                    payload_path.display()
                )))
            }
        }
        Value::Array(values) => {
            for value in values {
                validate_toml_value(value, payload_path)?;
            }
            Ok(())
        }
        Value::Object(object) => {
            for value in object.values() {
                validate_toml_value(value, payload_path)?;
            }
            Ok(())
        }
        Value::Bool(_) | Value::String(_) => Ok(()),
    }
}

pub fn is_control_key(key: &str) -> bool {
    matches!(key, DELETE_CONTROL | DELETE_PREFIXES_CONTROL)
}

fn invalid_control(payload_path: &Path, control: &str, reason: &str) -> AppError {
    AppError::new(format!(
        "agent-config-helper: invalid {control} control in {}: {reason}",
        payload_path.display()
    ))
}

fn invalid_control_entry(
    payload_path: &Path,
    control: &str,
    index: usize,
    reason: &str,
) -> AppError {
    invalid_control(payload_path, control, &format!("entry {index} {reason}"))
}
