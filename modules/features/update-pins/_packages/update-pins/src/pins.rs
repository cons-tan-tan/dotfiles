use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::error::UpdateError;

#[derive(Clone, Debug)]
pub struct PinDocument {
    path: PathBuf,
    value: Value,
    original: Vec<u8>,
    trailing_newline: bool,
    changed: bool,
}

impl PinDocument {
    pub fn parse(path: impl Into<PathBuf>, bytes: Vec<u8>) -> Result<Self, UpdateError> {
        let path = path.into();
        let value: Value =
            serde_json::from_slice(&bytes).map_err(|source| UpdateError::InvalidJson {
                path: path.clone(),
                source,
            })?;
        if !value.is_object() {
            return Err(UpdateError::ExpectedObject { path });
        }

        Ok(Self {
            path,
            value,
            trailing_newline: bytes.ends_with(b"\n"),
            original: bytes,
            changed: false,
        })
    }

    pub fn read(path: impl AsRef<Path>) -> Result<Self, UpdateError> {
        let path = path.as_ref();
        let bytes = std::fs::read(path).map_err(|source| UpdateError::io(path, source))?;
        Self::parse(path, bytes)
    }

    pub fn object(&self) -> &Map<String, Value> {
        self.value
            .as_object()
            .expect("PinDocument validates its root object when parsed")
    }

    pub fn string(&self, fields: &[&str]) -> Result<&str, UpdateError> {
        self.lookup(fields)
            .and_then(Value::as_str)
            .ok_or_else(|| UpdateError::InvalidStringField {
                path: self.path.clone(),
                field: fields.join("."),
            })
    }

    pub fn keys(&self, fields: &[&str]) -> Result<Vec<String>, UpdateError> {
        self.lookup(fields)
            .and_then(Value::as_object)
            .map(|object| object.keys().cloned().collect())
            .ok_or_else(|| {
                UpdateError::message(format!(
                    "{}: missing or invalid object field {}",
                    self.path.display(),
                    fields.join(".")
                ))
            })
    }

    pub fn set_string(
        &mut self,
        fields: &[&str],
        value: impl Into<String>,
    ) -> Result<(), UpdateError> {
        let value = value.into();
        let path = self.path.clone();
        let field = fields.join(".");
        let slot = lookup_mut(&mut self.value, fields)
            .ok_or(UpdateError::InvalidStringField { path, field })?;
        if !slot.is_string() {
            return Err(UpdateError::InvalidStringField {
                path: self.path.clone(),
                field: fields.join("."),
            });
        }
        if slot.as_str() != Some(&value) {
            *slot = Value::String(value);
            self.changed = true;
        }
        Ok(())
    }

    pub fn rendered(&self) -> Result<Option<Vec<u8>>, UpdateError> {
        if !self.changed {
            return Ok(None);
        }

        let mut rendered =
            serde_json::to_vec_pretty(&self.value).map_err(|source| UpdateError::InvalidJson {
                path: self.path.clone(),
                source,
            })?;
        if self.trailing_newline {
            rendered.push(b'\n');
        }
        if rendered == self.original {
            Ok(None)
        } else {
            Ok(Some(rendered))
        }
    }

    fn lookup(&self, fields: &[&str]) -> Option<&Value> {
        fields
            .iter()
            .try_fold(&self.value, |value, field| value.as_object()?.get(*field))
    }
}

fn lookup_mut<'a>(value: &'a mut Value, fields: &[&str]) -> Option<&'a mut Value> {
    let (first, rest) = fields.split_first()?;
    let child = value.as_object_mut()?.get_mut(*first)?;
    if rest.is_empty() {
        Some(child)
    } else {
        lookup_mut(child, rest)
    }
}

#[cfg(test)]
mod tests {
    use super::PinDocument;

    #[test]
    fn unchanged_document_returns_the_original_bytes_without_rendering() {
        let bytes = b"{\n  \"version\": \"1.2.3\"\n}\n".to_vec();
        let document = PinDocument::parse("pin.json", bytes).expect("valid pin");

        assert_eq!(document.rendered().expect("render pin"), None);
    }

    #[test]
    fn mutation_preserves_object_order_and_trailing_newline() {
        let bytes = b"{\n  \"version\": \"1.2.3\",\n  \"hash\": \"old\"\n}\n".to_vec();
        let mut document = PinDocument::parse("pin.json", bytes).expect("valid pin");

        document
            .set_string(&["version"], "2.0.0")
            .expect("existing string field");

        assert_eq!(
            document.rendered().expect("render pin"),
            Some(b"{\n  \"version\": \"2.0.0\",\n  \"hash\": \"old\"\n}\n".to_vec())
        );
    }

    #[test]
    fn mutation_preserves_absent_trailing_newline() {
        let bytes = br#"{"version":"1.2.3"}"#.to_vec();
        let mut document = PinDocument::parse("pin.json", bytes).expect("valid pin");

        document
            .set_string(&["version"], "2.0.0")
            .expect("existing string field");

        let rendered = document
            .rendered()
            .expect("render pin")
            .expect("changed pin");
        assert!(!rendered.ends_with(b"\n"));
    }

    #[test]
    fn nested_mutation_requires_an_existing_string_field() {
        let bytes = br#"{"assets":{"x86_64-linux":{"hash":"old"}}}"#.to_vec();
        let mut document = PinDocument::parse("pin.json", bytes).expect("valid pin");

        document
            .set_string(&["assets", "x86_64-linux", "hash"], "new")
            .expect("nested hash");
        assert_eq!(
            document
                .string(&["assets", "x86_64-linux", "hash"])
                .expect("updated hash"),
            "new"
        );
        assert!(
            document
                .set_string(&["assets", "missing", "hash"], "new")
                .is_err()
        );
    }
}
