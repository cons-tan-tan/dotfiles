use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

use serde_json::{Map, Number, Value as JsonValue};
use toml_edit::{
    Array, ArrayOfTables, DocumentMut, InlineTable, Item, Table, TableLike, Value as TomlValue,
};

use crate::error::{AppError, Result};
use crate::merge_payload::{self, MergePayload};

pub fn merge(source: &Path, payload: &Path, output: &Path) -> Result<()> {
    let payload_bytes =
        fs::read(payload).map_err(|error| AppError::io("read merge payload", payload, error))?;
    let payload = merge_payload::parse(&payload_bytes, payload)?;

    let source_exists = source.exists();
    let (mut document, output_mode) = if source_exists {
        let source_text = fs::read_to_string(source)
            .map_err(|error| AppError::io("read source TOML", source, error))?;
        let document = source_text
            .parse::<DocumentMut>()
            .map_err(|error| safe_toml_error(source, &source_text, &error))?;
        let mode = fs::metadata(source)
            .map_err(|error| AppError::io("inspect source TOML", source, error))?
            .permissions()
            .mode()
            & 0o7777;
        (document, mode)
    } else {
        (DocumentMut::new(), 0o600)
    };

    apply_payload(document.as_table_mut(), &payload)?;
    write_output(output, &document.to_string(), output_mode)
}

fn apply_payload(document: &mut Table, payload: &MergePayload) -> Result<()> {
    for path in &payload.delete_paths {
        delete_path(document, path);
    }
    for specification in &payload.delete_prefixes {
        delete_keys_with_prefix(document, &specification.path, &specification.prefix);
    }
    merge_table(document, &payload.values)
}

fn delete_path(destination: &mut dyn TableLike, path: &[String]) {
    let Some((key, rest)) = path.split_first() else {
        return;
    };
    if rest.is_empty() {
        destination.remove(key);
        return;
    }

    let remove_empty_child = {
        let Some(child) = destination.get_mut(key).and_then(Item::as_table_like_mut) else {
            return;
        };
        delete_path(child, rest);
        child.is_empty()
    };
    if remove_empty_child {
        destination.remove(key);
    }
}

fn delete_keys_with_prefix(destination: &mut dyn TableLike, path: &[String], prefix: &str) {
    let Some((key, rest)) = path.split_first() else {
        let keys: Vec<String> = destination
            .iter()
            .filter(|(key, _)| key.starts_with(prefix))
            .map(|(key, _)| key.to_owned())
            .collect();
        for key in keys {
            destination.remove(&key);
        }
        return;
    };
    let Some(child) = destination.get_mut(key).and_then(Item::as_table_like_mut) else {
        return;
    };
    delete_keys_with_prefix(child, rest, prefix);
}

fn merge_table(destination: &mut Table, source: &Map<String, JsonValue>) -> Result<()> {
    for (key, value) in source {
        if merge_payload::is_control_key(key) {
            continue;
        }
        if let JsonValue::Object(object) = value {
            let is_table_like = destination.get(key).is_some_and(Item::is_table_like);
            if !is_table_like {
                destination.insert(key, Item::Table(Table::new()));
            }
            match destination
                .get_mut(key)
                .expect("a table-like item was inserted")
            {
                Item::Table(child) => merge_table(child, object)?,
                Item::Value(TomlValue::InlineTable(child)) => {
                    merge_inline_table(child, object)?;
                }
                _ => unreachable!("the item was checked to be table-like"),
            }
        } else {
            let item = json_to_item(value)?;
            replace_table_item(destination, key, item);
        }
    }
    Ok(())
}

fn merge_inline_table(
    destination: &mut InlineTable,
    source: &Map<String, JsonValue>,
) -> Result<()> {
    for (key, value) in source {
        if merge_payload::is_control_key(key) {
            continue;
        }
        if let JsonValue::Object(object) = value {
            let is_table_like = destination.get(key).is_some_and(TomlValue::is_inline_table);
            if !is_table_like {
                destination.insert(key, TomlValue::InlineTable(InlineTable::new()));
            }
            let child = destination
                .get_mut(key)
                .and_then(TomlValue::as_inline_table_mut)
                .expect("an inline table was inserted");
            merge_inline_table(child, object)?;
        } else {
            let mut replacement = json_to_value(value)?;
            if let Some(existing) = destination.get_mut(key) {
                *replacement.decor_mut() = existing.decor().clone();
                *existing = replacement;
            } else {
                destination.insert(key, replacement);
            }
        }
    }
    Ok(())
}

fn replace_table_item(destination: &mut Table, key: &str, mut replacement: Item) {
    if let Some(existing) = destination.get_mut(key) {
        if let (Some(old), Some(new)) = (existing.as_value(), replacement.as_value_mut()) {
            *new.decor_mut() = old.decor().clone();
        }
        *existing = replacement;
    } else {
        destination.insert(key, replacement);
    }
}

fn json_to_item(value: &JsonValue) -> Result<Item> {
    match value {
        JsonValue::Object(object) => Ok(Item::Table(object_to_table(object)?)),
        JsonValue::Array(values)
            if !values.is_empty() && values.iter().all(JsonValue::is_object) =>
        {
            let mut tables = ArrayOfTables::new();
            for value in values {
                let object = value.as_object().expect("array object shape checked");
                tables.push(object_to_table_raw(object)?);
            }
            Ok(Item::ArrayOfTables(tables))
        }
        value => Ok(Item::Value(json_to_value(value)?)),
    }
}

fn json_to_value(value: &JsonValue) -> Result<TomlValue> {
    match value {
        JsonValue::Null => Err(unrepresentable_value()),
        JsonValue::Bool(value) => Ok(TomlValue::from(*value)),
        JsonValue::Number(value) => number_to_value(value),
        JsonValue::String(value) => Ok(TomlValue::from(value.clone())),
        JsonValue::Array(values) => {
            let mut array = Array::new();
            for value in values {
                array.push(json_to_value(value)?);
            }
            Ok(TomlValue::Array(array))
        }
        JsonValue::Object(object) => Ok(TomlValue::InlineTable(object_to_inline_table(object)?)),
    }
}

fn number_to_value(number: &Number) -> Result<TomlValue> {
    let representation = number.to_string();
    let is_float = representation
        .as_bytes()
        .iter()
        .any(|byte| matches!(byte, b'.' | b'e' | b'E'));
    if is_float {
        number
            .as_f64()
            .map(TomlValue::from)
            .ok_or_else(unrepresentable_value)
    } else {
        number
            .as_i64()
            .map(TomlValue::from)
            .ok_or_else(unrepresentable_value)
    }
}

fn object_to_table(object: &Map<String, JsonValue>) -> Result<Table> {
    let mut table = Table::new();
    merge_table(&mut table, object)?;
    Ok(table)
}

fn object_to_table_raw(object: &Map<String, JsonValue>) -> Result<Table> {
    let mut table = Table::new();
    for (key, value) in object {
        table.insert(key, json_to_item_raw(value)?);
    }
    Ok(table)
}

fn json_to_item_raw(value: &JsonValue) -> Result<Item> {
    match value {
        JsonValue::Object(object) => Ok(Item::Table(object_to_table_raw(object)?)),
        JsonValue::Array(values)
            if !values.is_empty() && values.iter().all(JsonValue::is_object) =>
        {
            let mut tables = ArrayOfTables::new();
            for value in values {
                let object = value.as_object().expect("array object shape checked");
                tables.push(object_to_table_raw(object)?);
            }
            Ok(Item::ArrayOfTables(tables))
        }
        value => Ok(Item::Value(json_to_value(value)?)),
    }
}

fn object_to_inline_table(object: &Map<String, JsonValue>) -> Result<InlineTable> {
    let mut table = InlineTable::new();
    for (key, value) in object {
        table.insert(key, json_to_value(value)?);
    }
    Ok(table)
}

fn unrepresentable_value() -> AppError {
    AppError::new("agent-config-helper: merge payload contains a value that TOML cannot represent")
}

fn safe_toml_error(path: &Path, source: &str, error: &toml_edit::TomlError) -> AppError {
    let location = error.span().map(|span| line_and_column(source, span.start));
    let location = location
        .map(|(line, column)| format!(" at line {line}, column {column}"))
        .unwrap_or_default();
    AppError::new(format!(
        "agent-config-helper: invalid TOML in {}{location}: {}",
        path.display(),
        error.message()
    ))
}

fn line_and_column(source: &str, byte_offset: usize) -> (usize, usize) {
    let prefix = &source.as_bytes()[..byte_offset.min(source.len())];
    let line = prefix.iter().filter(|byte| **byte == b'\n').count() + 1;
    let column = prefix
        .iter()
        .rev()
        .position(|byte| *byte == b'\n')
        .unwrap_or(prefix.len())
        + 1;
    (line, column)
}

fn write_output(path: &Path, content: &str, mode: u32) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)
        .map_err(|error| AppError::io("create output directory", parent, error))?;
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .map_err(|error| AppError::io("open output TOML", path, error))?;
    file.write_all(content.as_bytes())
        .map_err(|error| AppError::io("write output TOML", path, error))?;
    drop(file);
    fs::set_permissions(path, fs::Permissions::from_mode(mode & 0o7777))
        .map_err(|error| AppError::io("set output TOML mode on", path, error))
}
