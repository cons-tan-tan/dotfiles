use std::collections::BTreeSet;

use serde_json::Value;

use crate::cli::Target;
use crate::command::CommandRunner;
use crate::error::UpdateError;
use crate::pins::PinDocument;
use crate::registry::{AssetNaming, TargetKind, TargetSpec};
use crate::targets::paired_version;
use crate::transaction::Transaction;
use crate::upstream::validate_release_version;
use crate::value_validation::{validate_https_url, validate_sri_hash};

pub(crate) const CANONICAL_SYSTEMS: &[&str] = &[
    "aarch64-darwin",
    "x86_64-darwin",
    "aarch64-linux",
    "x86_64-linux",
];
const DARWIN_SYSTEMS: &[&str] = &["aarch64-darwin", "x86_64-darwin"];

pub fn validate_target_input<R: CommandRunner>(
    spec: &TargetSpec,
    transaction: &Transaction<'_, R>,
) -> Result<(), UpdateError> {
    match spec.kind {
        TargetKind::PairedRelease {
            repository,
            pin,
            input,
        } => {
            let document = load_pin(transaction, pin)?;
            validate_assets(
                spec,
                pin,
                &document,
                CANONICAL_SYSTEMS,
                AssetNaming::NameField,
            )?;
            let flake = transaction.read("flake.nix")?;
            let version = paired_input_version(&flake, input, repository)?;
            validate_release_version(spec.name, &version)
        }
        TargetKind::Release {
            pin,
            asset_naming,
            source_hash,
            ..
        } => {
            let document = load_pin(transaction, pin)?;
            validate_version_field(spec, pin, &document)?;
            let systems = if spec.target == Target::Watchexec {
                DARWIN_SYSTEMS
            } else {
                CANONICAL_SYSTEMS
            };
            validate_assets(spec, pin, &document, systems, asset_naming)?;
            if source_hash {
                validate_hash_field(spec, pin, &document, &["srcHash"])?;
            }
            Ok(())
        }
        TargetKind::UrlHash { pin } => {
            let document = load_pin(transaction, pin)?;
            validate_https_field(spec, pin, &document, &["url"])?;
            validate_hash_field(spec, pin, &document, &["hash"])
        }
        TargetKind::Shellfirm { pin, lock, .. } => {
            let document = load_pin(transaction, pin)?;
            validate_version_field(spec, pin, &document)?;
            validate_hash_field(spec, pin, &document, &["srcHash"])?;
            crate::shellfirm::validate_cargo_lock(
                spec.name,
                lock,
                &transaction.read(lock)?,
                document.string(&["version"])?,
            )
        }
        TargetKind::Difit {
            repository,
            pin,
            input,
            lock,
            ..
        } => {
            let document = load_pin(transaction, pin)?;
            validate_hash_field(spec, pin, &document, &["srcHash"])?;
            validate_hash_field(spec, pin, &document, &["npmDepsHash"])?;
            let flake = transaction.read("flake.nix")?;
            let version = paired_input_version(&flake, input, repository)?;
            validate_release_version(spec.name, &version)?;
            validate_difit_lock(spec, lock, &transaction.read(lock)?, &version)
        }
        TargetKind::CodexApp { pin } => {
            let document = load_pin(transaction, pin)?;
            validate_version_field(spec, pin, &document)?;
            validate_https_field(spec, pin, &document, &["appcast"])?;
            validate_https_field(spec, pin, &document, &["url"])?;
            validate_hash_field(spec, pin, &document, &["hash"])?;
            for field in ["appName", "bundleIdentifier", "displayName"] {
                validate_identity_field(spec, pin, &document, field)?;
            }
            Ok(())
        }
        TargetKind::Unimplemented => Err(UpdateError::message(format!(
            "{}: target is not implemented",
            spec.name
        ))),
    }
}

fn load_pin<R: CommandRunner>(
    transaction: &Transaction<'_, R>,
    path: &str,
) -> Result<PinDocument, UpdateError> {
    PinDocument::parse(path, transaction.read(path)?)
}

fn validate_version_field(
    spec: &TargetSpec,
    path: &str,
    document: &PinDocument,
) -> Result<(), UpdateError> {
    let version = required_string(spec, path, document, &["version"])?;
    validate_release_version(&format!("{}: {path}: version", spec.name), version)
}

fn validate_hash_field(
    spec: &TargetSpec,
    path: &str,
    document: &PinDocument,
    fields: &[&str],
) -> Result<(), UpdateError> {
    let hash = required_string(spec, path, document, fields)?;
    validate_sri_hash(
        &format!("{}: {path}: {}", spec.name, fields.join(".")),
        hash,
    )
}

fn validate_https_field(
    spec: &TargetSpec,
    path: &str,
    document: &PinDocument,
    fields: &[&str],
) -> Result<(), UpdateError> {
    let url = required_string(spec, path, document, fields)?;
    validate_https_url(&format!("{}: {path}: {}", spec.name, fields.join(".")), url)
}

fn validate_identity_field(
    spec: &TargetSpec,
    path: &str,
    document: &PinDocument,
    field: &str,
) -> Result<(), UpdateError> {
    let value = required_string(spec, path, document, &[field])?;
    if value.is_empty()
        || value.len() > 256
        || value.chars().any(char::is_control)
        || value.contains('/')
        || value.contains('\\')
    {
        Err(UpdateError::message(format!(
            "{}: {path}: {field}: expected a safe non-empty identity",
            spec.name
        )))
    } else {
        Ok(())
    }
}

fn validate_assets(
    spec: &TargetSpec,
    path: &str,
    document: &PinDocument,
    expected_systems: &[&str],
    naming: AssetNaming,
) -> Result<(), UpdateError> {
    let actual = document
        .keys(&["assets"])
        .map_err(|_| {
            UpdateError::message(format!(
                "{}: {path}: assets: missing or invalid object",
                spec.name
            ))
        })?
        .into_iter()
        .collect::<BTreeSet<_>>();
    let expected = expected_systems
        .iter()
        .map(|system| (*system).to_owned())
        .collect::<BTreeSet<_>>();
    if actual != expected {
        return Err(UpdateError::message(format!(
            "{}: {path}: assets: expected systems {}, found {}",
            spec.name,
            expected.into_iter().collect::<Vec<_>>().join(", "),
            actual.into_iter().collect::<Vec<_>>().join(", ")
        )));
    }
    for system in expected_systems {
        let naming_field = match naming {
            AssetNaming::NameField => "name",
            AssetNaming::WatchexecTarget => "target",
        };
        let name = required_string(spec, path, document, &["assets", system, naming_field])?;
        validate_asset_name(
            &format!("{}: {path}: assets.{system}.{naming_field}", spec.name),
            name,
        )?;
        validate_hash_field(spec, path, document, &["assets", system, "hash"])?;
    }
    Ok(())
}

fn validate_asset_name(label: &str, name: &str) -> Result<(), UpdateError> {
    if name.is_empty()
        || name.len() > 512
        || name.contains("..")
        || name.contains('/')
        || name.contains('\\')
        || name.chars().any(char::is_control)
    {
        Err(UpdateError::message(format!(
            "{label}: expected a safe non-empty asset name"
        )))
    } else {
        Ok(())
    }
}

fn required_string<'a>(
    spec: &TargetSpec,
    path: &str,
    document: &'a PinDocument,
    fields: &[&str],
) -> Result<&'a str, UpdateError> {
    document.string(fields).map_err(|_| {
        UpdateError::message(format!(
            "{}: {path}: {}: missing or invalid string",
            spec.name,
            fields.join(".")
        ))
    })
}

fn paired_input_version(
    bytes: &[u8],
    input: &str,
    repository: &str,
) -> Result<String, UpdateError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message("flake.nix: expected UTF-8"))?;
    let marker = format!("{input} = {{");
    let mut matches = Vec::new();
    let mut offset = 0_usize;
    for line in text.split_inclusive('\n') {
        let line_without_newline = line.trim_end_matches(['\r', '\n']);
        let trimmed = line_without_newline.trim_start();
        if trimmed == marker {
            matches.push(offset + line_without_newline.len() - trimmed.len());
        }
        offset += line.len();
    }
    if matches.len() != 1 {
        return Err(UpdateError::message(format!(
            "flake.nix: expected one input block for {input}, found {}",
            matches.len()
        )));
    }
    let block_start = matches[0];
    let brace_start = block_start + marker.len() - 1;
    let mut depth = 0_usize;
    let mut block_end = None;
    for (offset, character) in text[brace_start..].char_indices() {
        match character {
            '{' => depth += 1,
            '}' => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    block_end = Some(brace_start + offset + character.len_utf8());
                    break;
                }
            }
            _ => {}
        }
    }
    let block_end = block_end.ok_or_else(|| {
        UpdateError::message(format!("flake.nix: unterminated input block for {input}"))
    })?;
    let block_version = paired_version(&bytes[block_start..block_end], repository)?;
    let global_version = paired_version(bytes, repository)?;
    if block_version != global_version {
        return Err(UpdateError::message(format!(
            "flake.nix: input {input} does not uniquely own github:{repository}"
        )));
    }
    Ok(block_version)
}

fn validate_difit_lock(
    spec: &TargetSpec,
    path: &str,
    bytes: &[u8],
    expected_version: &str,
) -> Result<(), UpdateError> {
    let document: Value = serde_json::from_slice(bytes).map_err(|source| {
        UpdateError::message(format!("{}: {path}: invalid JSON: {source}", spec.name))
    })?;
    let top_name = document
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let top_version = document
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let root = document
        .get("packages")
        .and_then(Value::as_object)
        .and_then(|packages| packages.get(""))
        .and_then(Value::as_object)
        .ok_or_else(|| {
            UpdateError::message(format!(
                "{}: {path}: packages[\"\"]: missing root package",
                spec.name
            ))
        })?;
    let name = root.get("name").and_then(Value::as_str).unwrap_or_default();
    let version = root
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if top_name != "difit"
        || top_version != expected_version
        || name != "difit"
        || version != expected_version
    {
        return Err(UpdateError::message(format!(
            "{}: {path}: expected difit@{expected_version}, found {top_name}@{top_version} and root {name}@{version}",
            spec.name,
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::paired_input_version;

    #[test]
    fn paired_repository_must_belong_to_the_declared_input() {
        let valid = br#"
inputs = {
  hcom-src = {
    url = "github:aannoo/hcom/v1.2.3";
  };
};
"#;
        assert_eq!(
            paired_input_version(valid, "hcom-src", "aannoo/hcom").expect("paired input"),
            "1.2.3"
        );

        let swapped = br#"
inputs = {
  hcom-src = {
    url = "github:someone/else/v1.2.3";
  };
  unrelated = {
    url = "github:aannoo/hcom/v1.2.3";
  };
};
"#;
        assert!(paired_input_version(swapped, "hcom-src", "aannoo/hcom").is_err());

        let prefixed = br#"
inputs = {
  old-hcom-src = {
    url = "github:aannoo/hcom/v1.2.3";
  };
};
"#;
        assert!(paired_input_version(prefixed, "hcom-src", "aannoo/hcom").is_err());
    }
}
