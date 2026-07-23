use std::collections::BTreeSet;
use std::fs::File;
use std::io::Read as _;
use std::path::{Component, Path, PathBuf};

use toml::Value;

use crate::build::build_package_once;
use crate::command::CommandRunner;
use crate::error::UpdateError;
use crate::policy::RunPolicy;
use crate::prefetch::prefetch_result;
use crate::registry::TargetSpec;
use crate::targets::{latest_tag, load_pin, validate_release_version, write_pin};
use crate::transaction::Transaction;

const MAX_SOURCE_ROOT_ENTRIES: usize = 4_096;
const MAX_WORKSPACE_MEMBERS: usize = 1_024;
const MAX_MANIFEST_BYTES: usize = 1024 * 1024;
const MAX_TOTAL_MANIFEST_BYTES: usize = 8 * 1024 * 1024;
const MAX_LOCK_BYTES: usize = 16 * 1024 * 1024;
const CRATES_IO_REGISTRY: &str = "registry+https://github.com/rust-lang/crates.io-index";

#[allow(clippy::too_many_arguments)]
pub fn update<R: CommandRunner>(
    spec: &TargetSpec,
    repository: &str,
    pin_path: &str,
    lock_path: &str,
    package: &str,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let tag = latest_tag(policy, runner, transaction.root(), repository)?;
    let version = tag.strip_prefix('v').unwrap_or(&tag);
    validate_release_version(spec.name, version)?;

    let mut pin = load_pin(transaction, pin_path)?;
    let current_version = pin.string(&["version"])?.to_owned();
    if version == current_version && !policy.force {
        println!("{}: {current_version} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: prefetching candidate {version} (current {current_version})...",
        spec.name
    );
    let source_url = format!("https://github.com/{repository}/archive/refs/tags/{tag}.tar.gz");
    let source = prefetch_result(
        &format!("{}: {pin_path}: srcHash", spec.name),
        policy,
        runner,
        transaction.root(),
        &source_url,
        true,
    )?;
    let store_path = source.store_path.ok_or_else(|| {
        UpdateError::message(format!(
            "{}: prefetch did not return an unpacked store path for {source_url}",
            spec.name
        ))
    })?;
    let candidate_lock = read_lock_from_source(spec.name, &store_path, version)?;

    let current_source_hash = pin.string(&["srcHash"])?.to_owned();
    let current_lock = transaction.read(lock_path)?;
    let changed = current_version != version
        || current_source_hash != source.hash
        || current_lock != candidate_lock;

    pin.set_string(&["version"], version)?;
    pin.set_string(&["srcHash"], source.hash)?;
    write_pin(transaction, pin_path, &pin)?;
    transaction.write_if_changed(lock_path, &candidate_lock)?;

    build_package_once(spec.name, package, runner, transaction)?;
    if !changed {
        println!("{}: candidate source and lockfile are unchanged", spec.name);
    }
    Ok(changed)
}

pub fn validate_cargo_lock(
    label: &str,
    path: &str,
    bytes: &[u8],
    expected_version: &str,
) -> Result<(), UpdateError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message(format!("{label}: {path}: lockfile is not UTF-8")))?;
    let document: Value = toml::from_str(text).map_err(|source| {
        UpdateError::message(format!(
            "{label}: {path}: invalid Cargo.lock TOML: {source}"
        ))
    })?;
    let format = document
        .get("version")
        .and_then(Value::as_integer)
        .ok_or_else(|| {
            UpdateError::message(format!("{label}: {path}: missing integer lockfile version"))
        })?;
    if !matches!(format, 3 | 4) {
        return Err(UpdateError::message(format!(
            "{label}: {path}: unsupported Cargo.lock format version {format}"
        )));
    }
    let packages = document
        .get("package")
        .and_then(Value::as_array)
        .ok_or_else(|| UpdateError::message(format!("{label}: {path}: missing package entries")))?;
    let mut identities = BTreeSet::new();
    let mut shellfirm_root_count = 0_usize;
    let mut matching_shellfirm_root_count = 0_usize;
    for (index, package) in packages.iter().enumerate() {
        let package = package.as_table().ok_or_else(|| {
            UpdateError::message(format!(
                "{label}: {path}: package entry {index} is not a table"
            ))
        })?;
        let name = package
            .get("name")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                UpdateError::message(format!(
                    "{label}: {path}: package entry {index} has no name"
                ))
            })?;
        let version = package
            .get("version")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                UpdateError::message(format!("{label}: {path}: package {name} has no version"))
            })?;
        let source = match package.get("source") {
            Some(Value::String(source)) => Some(source.as_str()),
            Some(_) => {
                return Err(UpdateError::message(format!(
                    "{label}: {path}: package {name} {version} has a non-string source"
                )));
            }
            None => None,
        };
        let identity = (name, version, source.unwrap_or(""));
        if !identities.insert(identity) {
            return Err(UpdateError::message(format!(
                "{label}: {path}: duplicate package {name} {version}"
            )));
        }

        match source {
            Some(source) if source.starts_with("git+") => {
                return Err(UpdateError::message(format!(
                    "{label}: {path}: git dependency is unsupported: {name} {version}"
                )));
            }
            Some(CRATES_IO_REGISTRY) => {
                let checksum = package
                    .get("checksum")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                if checksum.len() != 64
                    || !checksum
                        .bytes()
                        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
                {
                    return Err(UpdateError::message(format!(
                        "{label}: {path}: registry package {name} {version} has no valid checksum"
                    )));
                }
            }
            Some(source) => {
                return Err(UpdateError::message(format!(
                    "{label}: {path}: unsupported dependency source for {name} {version}: {source}"
                )));
            }
            None if name == "shellfirm" => {
                shellfirm_root_count += 1;
                if version == expected_version {
                    matching_shellfirm_root_count += 1;
                }
            }
            None => {}
        }
    }
    if shellfirm_root_count != 1 || matching_shellfirm_root_count != 1 {
        return Err(UpdateError::message(format!(
            "{label}: {path}: expected exactly one source-free shellfirm {expected_version} package, found {shellfirm_root_count} shellfirm roots"
        )));
    }
    Ok(())
}

fn read_lock_from_source(
    label: &str,
    store_path: &Path,
    expected_version: &str,
) -> Result<Vec<u8>, UpdateError> {
    if !store_path.is_absolute() {
        return Err(UpdateError::message(format!(
            "{label}: prefetch returned a non-absolute store path {}",
            store_path.display()
        )));
    }
    let metadata = std::fs::symlink_metadata(store_path)
        .map_err(|source| UpdateError::io(store_path, source))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(UpdateError::message(format!(
            "{label}: unpacked store path is not a regular directory: {}",
            store_path.display()
        )));
    }

    let roots = discover_source_roots(label, store_path)?;
    let [(manifest_path, lock_path)] = roots.as_slice() else {
        return Err(UpdateError::message(format!(
            "{label}: expected exactly one directory containing regular Cargo.toml and Cargo.lock files, found {}",
            roots.len()
        )));
    };
    let root_manifest = read_bounded(label, manifest_path, MAX_MANIFEST_BYTES)?;
    let root_document = parse_manifest(label, manifest_path, &root_manifest)?;
    let source_root = manifest_path
        .parent()
        .expect("a Cargo.toml candidate always has a parent directory");
    validate_package_manifest(
        label,
        source_root,
        &root_document,
        root_manifest.len(),
        expected_version,
    )?;

    let lock = read_bounded(label, lock_path, MAX_LOCK_BYTES)?;
    validate_cargo_lock(
        label,
        &lock_path.display().to_string(),
        &lock,
        expected_version,
    )?;
    Ok(lock)
}

fn discover_source_roots(label: &str, root: &Path) -> Result<Vec<(PathBuf, PathBuf)>, UpdateError> {
    let mut roots = Vec::new();
    let mut candidates = vec![root.to_owned()];
    let entries = std::fs::read_dir(root).map_err(|source| UpdateError::io(root, source))?;
    for (index, entry) in entries.enumerate() {
        if index >= MAX_SOURCE_ROOT_ENTRIES {
            return Err(UpdateError::message(format!(
                "{label}: unpacked source has more than {MAX_SOURCE_ROOT_ENTRIES} root entries"
            )));
        }
        let entry = entry.map_err(|source| UpdateError::io(root, source))?;
        let file_type = entry
            .file_type()
            .map_err(|source| UpdateError::io(entry.path(), source))?;
        if file_type.is_dir() {
            candidates.push(entry.path());
        }
    }
    candidates.sort();

    for directory in candidates {
        let manifest = directory.join("Cargo.toml");
        let lock = directory.join("Cargo.lock");
        let has_manifest = regular_file_if_present(label, &manifest)?;
        let has_lock = regular_file_if_present(label, &lock)?;
        if has_manifest && has_lock {
            roots.push((manifest, lock));
        }
    }
    Ok(roots)
}

fn regular_file_if_present(label: &str, path: &Path) -> Result<bool, UpdateError> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_file() => Ok(true),
        Ok(_) => Err(UpdateError::message(format!(
            "{label}: {} must be a regular non-symlink file",
            path.display()
        ))),
        Err(source) if source.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(source) => Err(UpdateError::io(path, source)),
    }
}

fn read_bounded(label: &str, path: &Path, limit: usize) -> Result<Vec<u8>, UpdateError> {
    let file = File::open(path).map_err(|source| UpdateError::io(path, source))?;
    let mut bytes = Vec::new();
    file.take(limit as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|source| UpdateError::io(path, source))?;
    if bytes.len() > limit {
        return Err(UpdateError::message(format!(
            "{label}: {} exceeds the {limit}-byte limit",
            path.display()
        )));
    }
    Ok(bytes)
}

fn parse_manifest(label: &str, path: &Path, bytes: &[u8]) -> Result<Value, UpdateError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message(format!("{label}: {} is not UTF-8", path.display())))?;
    toml::from_str(text).map_err(|source| {
        UpdateError::message(format!(
            "{label}: invalid manifest {}: {source}",
            path.display()
        ))
    })
}

fn validate_package_manifest(
    label: &str,
    source_root: &Path,
    root_document: &Value,
    root_manifest_size: usize,
    expected_version: &str,
) -> Result<(), UpdateError> {
    let mut matches = 0_usize;
    validate_manifest_package(
        label,
        &source_root.join("Cargo.toml"),
        root_document,
        expected_version,
        &mut matches,
        false,
    )?;

    let members = root_document
        .get("workspace")
        .and_then(Value::as_table)
        .and_then(|workspace| workspace.get("members"));
    let mut total_manifest_bytes = root_manifest_size;
    if let Some(members) = members {
        let members = members.as_array().ok_or_else(|| {
            UpdateError::message(format!(
                "{label}: {}: workspace.members must be an array",
                source_root.join("Cargo.toml").display()
            ))
        })?;
        if members.len() > MAX_WORKSPACE_MEMBERS {
            return Err(UpdateError::message(format!(
                "{label}: workspace has more than {MAX_WORKSPACE_MEMBERS} members"
            )));
        }
        for member in members {
            let member = member.as_str().ok_or_else(|| {
                UpdateError::message(format!("{label}: workspace member must be a string"))
            })?;
            let relative = Path::new(member);
            if relative.as_os_str().is_empty()
                || relative.is_absolute()
                || relative
                    .components()
                    .any(|component| !matches!(component, Component::Normal(_)))
                || member.contains(['*', '?', '[', ']'])
            {
                return Err(UpdateError::message(format!(
                    "{label}: unsupported workspace member path '{member}'"
                )));
            }
            let path = workspace_member_manifest(label, source_root, relative)?;
            let bytes = read_bounded(label, &path, MAX_MANIFEST_BYTES)?;
            total_manifest_bytes =
                total_manifest_bytes
                    .checked_add(bytes.len())
                    .ok_or_else(|| {
                        UpdateError::message(format!("{label}: manifest byte count overflowed"))
                    })?;
            if total_manifest_bytes > MAX_TOTAL_MANIFEST_BYTES {
                return Err(UpdateError::message(format!(
                    "{label}: workspace manifests exceed {MAX_TOTAL_MANIFEST_BYTES} bytes"
                )));
            }
            let document = parse_manifest(label, &path, &bytes)?;
            validate_manifest_package(
                label,
                &path,
                &document,
                expected_version,
                &mut matches,
                true,
            )?;
        }
    }
    if matches != 1 {
        return Err(UpdateError::message(format!(
            "{label}: expected exactly one shellfirm {expected_version} package manifest, found {matches}"
        )));
    }
    Ok(())
}

fn workspace_member_manifest(
    label: &str,
    source_root: &Path,
    relative: &Path,
) -> Result<PathBuf, UpdateError> {
    let mut directory = source_root.to_owned();
    for component in relative.components() {
        let Component::Normal(component) = component else {
            unreachable!("workspace member paths are validated before traversal");
        };
        directory.push(component);
        let metadata = std::fs::symlink_metadata(&directory)
            .map_err(|source| UpdateError::io(&directory, source))?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(UpdateError::message(format!(
                "{label}: workspace member path component is not a regular directory: {}",
                directory.display()
            )));
        }
    }
    let manifest = directory.join("Cargo.toml");
    if !regular_file_if_present(label, &manifest)? {
        return Err(UpdateError::message(format!(
            "{label}: workspace member manifest is missing: {}",
            manifest.display()
        )));
    }
    Ok(manifest)
}

fn validate_manifest_package(
    label: &str,
    path: &Path,
    document: &Value,
    expected_version: &str,
    matches: &mut usize,
    package_required: bool,
) -> Result<(), UpdateError> {
    let Some(package) = document.get("package").and_then(Value::as_table) else {
        if package_required {
            return Err(UpdateError::message(format!(
                "{label}: workspace member {} has no package table",
                path.display()
            )));
        }
        return Ok(());
    };
    let name = package
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            UpdateError::message(format!(
                "{label}: package manifest {} has no name",
                path.display()
            ))
        })?;
    let version = package
        .get("version")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            UpdateError::message(format!(
                "{label}: package manifest {} has no version",
                path.display()
            ))
        })?;
    if name == "shellfirm" {
        if version != expected_version {
            return Err(UpdateError::message(format!(
                "{label}: {} declares shellfirm {version}, expected {expected_version}",
                path.display()
            )));
        }
        *matches += 1;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::TempDir;

    use super::{CRATES_IO_REGISTRY, read_lock_from_source, validate_cargo_lock};

    const VALID_LOCK: &str = r#"
version = 4

[[package]]
name = "dependency"
version = "1.2.3"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

[[package]]
name = "shellfirm"
version = "9.9.9"
"#;

    #[test]
    fn validates_format_root_and_registry_checksums() {
        validate_cargo_lock("shellfirm", "Cargo.lock", VALID_LOCK.as_bytes(), "9.9.9")
            .expect("valid lock");
    }

    #[test]
    fn rejects_unsupported_sources_missing_checksums_and_wrong_root() {
        let git = VALID_LOCK.replace(
            "registry+https://github.com/rust-lang/crates.io-index",
            "git+https://example.invalid/repository",
        );
        assert!(validate_cargo_lock("shellfirm", "Cargo.lock", git.as_bytes(), "9.9.9").is_err());
        let non_string_source = VALID_LOCK.replace(
            "source = \"registry+https://github.com/rust-lang/crates.io-index\"",
            "source = [\"git+https://example.invalid/repository\"]",
        );
        assert!(
            validate_cargo_lock(
                "shellfirm",
                "Cargo.lock",
                non_string_source.as_bytes(),
                "9.9.9"
            )
            .is_err()
        );
        let alternate_registry =
            VALID_LOCK.replace(CRATES_IO_REGISTRY, "registry+https://example.invalid/index");
        assert!(
            validate_cargo_lock(
                "shellfirm",
                "Cargo.lock",
                alternate_registry.as_bytes(),
                "9.9.9"
            )
            .is_err()
        );

        let missing_checksum = VALID_LOCK
            .lines()
            .filter(|line| !line.starts_with("checksum ="))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(
            validate_cargo_lock(
                "shellfirm",
                "Cargo.lock",
                missing_checksum.as_bytes(),
                "9.9.9"
            )
            .is_err()
        );
        assert!(
            validate_cargo_lock("shellfirm", "Cargo.lock", VALID_LOCK.as_bytes(), "8.8.8").is_err()
        );
        let duplicate_root =
            format!("{VALID_LOCK}\n[[package]]\nname = \"shellfirm\"\nversion = \"8.8.8\"\n");
        assert!(
            validate_cargo_lock(
                "shellfirm",
                "Cargo.lock",
                duplicate_root.as_bytes(),
                "9.9.9"
            )
            .is_err()
        );
    }

    #[test]
    fn reads_one_workspace_lock_without_rewriting_it() {
        let source = source_fixture();
        let bytes =
            read_lock_from_source("shellfirm", source.path(), "9.9.9").expect("source lock");
        assert_eq!(bytes, VALID_LOCK.as_bytes());

        let wrapped = TempDir::new().expect("temporary wrapper");
        populate_source(&wrapped.path().join("shellfirm-9.9.9"));
        let bytes =
            read_lock_from_source("shellfirm", wrapped.path(), "9.9.9").expect("wrapped lock");
        assert_eq!(bytes, VALID_LOCK.as_bytes());
    }

    #[test]
    fn rejects_missing_ambiguous_and_symlinked_layouts() {
        let missing = TempDir::new().expect("temporary source");
        fs::write(missing.path().join("Cargo.toml"), "[workspace]\n").expect("workspace manifest");
        assert!(read_lock_from_source("shellfirm", missing.path(), "9.9.9").is_err());

        let ambiguous = source_fixture();
        let nested = ambiguous.path().join("nested");
        fs::create_dir(&nested).expect("nested source");
        fs::write(nested.join("Cargo.toml"), "[workspace]\n").expect("nested manifest");
        fs::write(nested.join("Cargo.lock"), "version = 4\n").expect("nested lock");
        assert!(read_lock_from_source("shellfirm", ambiguous.path(), "9.9.9").is_err());

        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;

            let symlinked = TempDir::new().expect("temporary source");
            fs::write(symlinked.path().join("real.toml"), "[workspace]\n").expect("real manifest");
            symlink(
                symlinked.path().join("real.toml"),
                symlinked.path().join("Cargo.toml"),
            )
            .expect("manifest symlink");
            fs::write(symlinked.path().join("Cargo.lock"), VALID_LOCK).expect("lock");
            assert!(read_lock_from_source("shellfirm", symlinked.path(), "9.9.9").is_err());

            let member_symlink = TempDir::new().expect("temporary source");
            let outside = TempDir::new().expect("outside package");
            populate_source(member_symlink.path());
            fs::remove_dir_all(member_symlink.path().join("shellfirm"))
                .expect("remove package directory");
            fs::write(
                outside.path().join("Cargo.toml"),
                "[package]\nname = \"shellfirm\"\nversion = \"9.9.9\"\n",
            )
            .expect("outside manifest");
            symlink(outside.path(), member_symlink.path().join("shellfirm"))
                .expect("member directory symlink");
            assert!(read_lock_from_source("shellfirm", member_symlink.path(), "9.9.9").is_err());
        }
    }

    fn source_fixture() -> TempDir {
        let source = TempDir::new().expect("temporary source");
        populate_source(source.path());
        source
    }

    fn populate_source(path: &std::path::Path) {
        fs::create_dir_all(path).expect("source directory");
        fs::write(
            path.join("Cargo.toml"),
            "[workspace]\nmembers = [\"shellfirm\"]\n",
        )
        .expect("workspace manifest");
        fs::write(path.join("Cargo.lock"), VALID_LOCK).expect("lock");
        let package = path.join("shellfirm");
        fs::create_dir(&package).expect("package directory");
        fs::write(
            package.join("Cargo.toml"),
            "[package]\nname = \"shellfirm\"\nversion = \"9.9.9\"\n",
        )
        .expect("package manifest");
    }
}
