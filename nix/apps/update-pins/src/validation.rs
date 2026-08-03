use std::collections::BTreeSet;

use crate::cli::Target;
use crate::command::CommandRunner;
use crate::error::UpdateError;
use crate::pins::PinDocument;
use crate::registry::{AssetNaming, PairedSource, TargetKind, TargetSpec};
use crate::targets::paired_input_version;
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
        TargetKind::PairedRelease { pin, source } => {
            let document = load_pin(transaction, pin)?;
            validate_assets(
                spec,
                pin,
                &document,
                CANONICAL_SYSTEMS,
                AssetNaming::NameField,
            )?;
            let version = validate_paired_source(source, transaction)?;
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
        TargetKind::Shellfirm {
            pin,
            lock,
            guard_manifest,
            guard_lock,
            ..
        } => {
            let document = load_pin(transaction, pin)?;
            validate_version_field(spec, pin, &document)?;
            validate_hash_field(spec, pin, &document, &["srcHash"])?;
            crate::shellfirm::validate_cargo_lock(
                spec.name,
                lock,
                &transaction.read(lock)?,
                document.string(&["version"])?,
            )?;
            crate::shellfirm::validate_guard_manifest(
                spec.name,
                guard_manifest,
                &transaction.read(guard_manifest)?,
                document.string(&["version"])?,
            )?;
            crate::shellfirm::validate_guard_lock(
                spec.name,
                guard_lock,
                &transaction.read(guard_lock)?,
                document.string(&["version"])?,
            )
        }
        TargetKind::PublishedNodePackage(package) => {
            let document = load_pin(transaction, package.pin)?;
            let crate::registry::PublishedArtifact::NpmRegistryTarball {
                source_hash_field, ..
            } = package.artifact;
            validate_hash_field(spec, package.pin, &document, &[source_hash_field])?;
            validate_hash_field(
                spec,
                package.pin,
                &document,
                &[package.build.dependency_hash_field],
            )?;
            let paired = package.dependencies.source();
            let version = validate_paired_source(paired, transaction)?;
            validate_release_version(spec.name, &version)
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

fn validate_paired_source<R: CommandRunner>(
    source: PairedSource,
    transaction: &Transaction<'_, R>,
) -> Result<String, UpdateError> {
    let authority = source.authority;
    let source_bytes = transaction.read(authority.source_path)?;
    let source_version = paired_input_version(
        &source_bytes,
        authority.source_path,
        source.input,
        source.repository,
    )?;
    let generated_bytes = transaction.read(authority.generated_flake_path)?;
    let generated_version = paired_input_version(
        &generated_bytes,
        authority.generated_flake_path,
        source.input,
        source.repository,
    )?;
    if source_version != generated_version {
        return Err(UpdateError::message(format!(
            "{}: input {} has v{source_version}, but {} has v{generated_version}",
            authority.source_path, source.input, authority.generated_flake_path
        )));
    }
    Ok(source_version)
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

#[cfg(test)]
mod tests {
    use crate::targets::paired_input_version;

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
            paired_input_version(valid, "flake.nix", "hcom-src", "aannoo/hcom")
                .expect("paired input"),
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
        assert!(paired_input_version(swapped, "flake.nix", "hcom-src", "aannoo/hcom").is_err());

        let prefixed = br#"
inputs = {
  old-hcom-src = {
    url = "github:aannoo/hcom/v1.2.3";
  };
};
"#;
        assert!(paired_input_version(prefixed, "flake.nix", "hcom-src", "aannoo/hcom").is_err());
    }
}
