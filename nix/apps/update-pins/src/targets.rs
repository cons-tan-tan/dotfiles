use std::fs::File;
use std::io::{Read as _, Write as _};
use std::path::{Component, Path};

use flate2::read::GzDecoder;
use serde_json::Value;

use crate::build::compute_hash_via_failed_build;
use crate::cli::Target;
use crate::codex_app;
use crate::command::{CommandRunner, CommandSpec, run_checked};
use crate::error::UpdateError;
use crate::pins::PinDocument;
use crate::prefetch::{prefetch_hash as prefetch, prefetch_result};
use crate::registry::{AssetNaming, TargetKind, TargetSpec, target_spec};
use crate::transaction::Transaction;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TargetResult {
    pub changed: bool,
}

pub fn is_implemented(target: Target) -> bool {
    target_spec(target).is_some_and(|spec| spec.kind.is_implemented())
}

pub fn run_target<R: CommandRunner>(
    target: Target,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<TargetResult, UpdateError> {
    let Some(spec) = target_spec(target) else {
        return Err(UpdateError::message(format!(
            "update-pins: Rust updater for {} is not yet implemented",
            target.name()
        )));
    };
    let changed = match spec.kind {
        TargetKind::PairedRelease {
            repository,
            pin,
            input,
        } => update_paired_release(spec, repository, pin, input, runner, transaction)?,
        TargetKind::Release {
            repository,
            pin,
            asset_naming,
            source_hash,
        } => update_release(
            spec,
            repository,
            pin,
            asset_naming,
            source_hash,
            runner,
            transaction,
        )?,
        TargetKind::UrlHash { pin } => update_url_hash(spec, pin, runner, transaction)?,
        TargetKind::Shellfirm {
            repository,
            pin,
            package,
        } => update_shellfirm(spec, repository, pin, package, runner, transaction)?,
        TargetKind::Difit {
            repository,
            npm_package,
            pin,
            input,
            lock,
            package,
        } => update_difit(
            spec,
            repository,
            npm_package,
            pin,
            input,
            lock,
            package,
            runner,
            transaction,
        )?,
        TargetKind::CodexApp { pin } => codex_app::update(spec, pin, runner, transaction)?,
        TargetKind::Unimplemented => {
            return Err(UpdateError::message(format!(
                "update-pins: Rust updater for {} is not yet implemented",
                spec.name
            )));
        }
    };
    Ok(TargetResult { changed })
}

fn update_paired_release<R: CommandRunner>(
    spec: &TargetSpec,
    repository: &str,
    pin_path: &str,
    input: &str,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let tag = latest_tag(runner, transaction.root(), repository)?;
    let Some(version) = tag.strip_prefix('v') else {
        return Err(UpdateError::message(format!(
            "{}: unsupported release tag '{tag}'",
            spec.name
        )));
    };
    validate_release_version(spec.name, version)?;

    let flake = transaction.read("flake.nix")?;
    let current = paired_version(&flake, repository)?;
    if version == current {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: {current} -> {version} (prefetching assets...)",
        spec.name
    );
    let mut pin = load_pin(transaction, pin_path)?;
    refresh_assets(
        &mut pin,
        repository,
        &tag,
        version,
        AssetNaming::NameField,
        runner,
        transaction.root(),
    )?;
    write_pin(transaction, pin_path, &pin)?;

    update_paired_flake_input(input, repository, version, &flake, runner, transaction)?;
    Ok(true)
}

fn update_release<R: CommandRunner>(
    spec: &TargetSpec,
    repository: &str,
    pin_path: &str,
    asset_naming: AssetNaming,
    source_hash: bool,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let mut pin = load_pin(transaction, pin_path)?;
    let current = pin.string(&["version"])?.to_owned();
    let tag = latest_tag(runner, transaction.root(), repository)?;
    let version = tag.strip_prefix('v').unwrap_or(&tag);
    if version == current {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: {current} -> {version} (prefetching assets...)",
        spec.name
    );
    pin.set_string(&["version"], version)?;
    refresh_assets(
        &mut pin,
        repository,
        &tag,
        version,
        asset_naming,
        runner,
        transaction.root(),
    )?;
    if source_hash {
        println!("{}: updating srcHash", spec.name);
        let source_url =
            format!("https://github.com/{repository}/archive/refs/tags/v{version}.tar.gz");
        let hash = prefetch(runner, transaction.root(), &source_url, true)?;
        pin.set_string(&["srcHash"], hash)?;
    }
    write_pin(transaction, pin_path, &pin)?;
    Ok(true)
}

fn update_url_hash<R: CommandRunner>(
    spec: &TargetSpec,
    pin_path: &str,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let mut pin = load_pin(transaction, pin_path)?;
    let url = pin.string(&["url"])?.to_owned();
    let current = pin.string(&["hash"])?.to_owned();
    println!("{}: checking schema hash...", spec.name);
    let hash = prefetch(runner, transaction.root(), &url, false)?;
    if hash == current {
        println!("{}: up to date", spec.name);
        return Ok(false);
    }
    pin.set_string(&["hash"], hash)?;
    write_pin(transaction, pin_path, &pin)?;
    println!("{}: hash updated", spec.name);
    Ok(true)
}

fn update_shellfirm<R: CommandRunner>(
    spec: &TargetSpec,
    repository: &str,
    pin_path: &str,
    package: &str,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let tag = latest_tag(runner, transaction.root(), repository)?;
    let version = tag.strip_prefix('v').unwrap_or(&tag);
    validate_release_version(spec.name, version)?;

    let mut pin = load_pin(transaction, pin_path)?;
    let current = pin.string(&["version"])?.to_owned();
    if version == current {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: {current} -> {version} (prefetching source...)",
        spec.name
    );
    let source_url = format!("https://github.com/{repository}/archive/refs/tags/{tag}.tar.gz");
    let source_hash = prefetch(runner, transaction.root(), &source_url, true)?;
    pin.set_string(&["version"], version)?;
    pin.set_string(&["srcHash"], source_hash)?;
    pin.set_string(&["cargoHash"], "")?;
    write_pin(transaction, pin_path, &pin)?;
    compute_hash_via_failed_build(
        spec.name,
        package,
        pin_path,
        "cargoHash",
        &mut pin,
        runner,
        transaction,
    )?;
    Ok(true)
}

#[allow(clippy::too_many_arguments)]
fn update_difit<R: CommandRunner>(
    spec: &TargetSpec,
    repository: &str,
    npm_package: &str,
    pin_path: &str,
    input: &str,
    lock_path: &str,
    package: &str,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let flake = transaction.read("flake.nix")?;
    let current = paired_version(&flake, repository)?;
    let version = latest_npm_version(runner, transaction.root(), npm_package)?;
    validate_release_version(spec.name, &version)?;
    if version == current {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: {current} -> {version} (prefetching source...)",
        spec.name
    );
    let source_url =
        format!("https://registry.npmjs.org/{npm_package}/-/{npm_package}-{version}.tgz");
    let source = prefetch_result(runner, transaction.root(), &source_url, false)?;
    let archive_path = source.store_path.ok_or_else(|| {
        UpdateError::message(format!(
            "{}: prefetch did not return a store path for {source_url}",
            spec.name
        ))
    })?;
    if !archive_path.is_absolute() {
        return Err(UpdateError::message(format!(
            "{}: prefetch returned a non-absolute store path {}",
            spec.name,
            archive_path.display()
        )));
    }
    require_regular_file(
        &archive_path,
        &format!(
            "{}: prefetch store path is not a regular file: {}",
            spec.name,
            archive_path.display()
        ),
    )?;
    let temporary = tempfile::tempdir()
        .map_err(|source| UpdateError::io("<difit temporary directory>", source))?;
    let package_dir = temporary.path().join("package");
    std::fs::create_dir(&package_dir).map_err(|source| UpdateError::io(&package_dir, source))?;
    let package_json = read_npm_package_json(&archive_path, spec.name)?;
    validate_npm_identity(
        &package_json,
        npm_package,
        &version,
        &format!("{} package.json", spec.name),
    )?;
    let package_json_path = package_dir.join("package.json");
    std::fs::write(&package_json_path, package_json)
        .map_err(|source| UpdateError::io(&package_json_path, source))?;
    let npm = CommandSpec::new("npm")
        .args([
            "install",
            "--package-lock-only",
            "--ignore-scripts",
            "--no-audit",
            "--no-fund",
        ])
        .current_dir(&package_dir);
    let npm_output = run_checked(runner, &npm)?;
    forward_output(&npm_output.stdout, &npm_output.stderr)?;

    let generated_lock = package_dir.join("package-lock.json");
    require_regular_file(
        &generated_lock,
        &format!("{}: npm did not generate package-lock.json", spec.name),
    )?;
    let lock_bytes = std::fs::read(&generated_lock)
        .map_err(|source| UpdateError::io(&generated_lock, source))?;
    validate_npm_lock(&lock_bytes, npm_package, &version, spec.name)?;
    transaction.replace(lock_path, &lock_bytes)?;

    let mut pin = load_pin(transaction, pin_path)?;
    pin.set_string(&["srcHash"], source.hash)?;
    pin.set_string(&["npmDepsHash"], "")?;
    write_pin(transaction, pin_path, &pin)?;
    update_paired_flake_input(input, repository, &version, &flake, runner, transaction)?;
    compute_hash_via_failed_build(
        spec.name,
        package,
        pin_path,
        "npmDepsHash",
        &mut pin,
        runner,
        transaction,
    )?;
    Ok(true)
}

fn latest_npm_version<R: CommandRunner>(
    runner: &R,
    root: &Path,
    package: &str,
) -> Result<String, UpdateError> {
    let url = format!("https://registry.npmjs.org/{package}/latest");
    let command = CommandSpec::new("curl")
        .args(["-fsSL", &url])
        .current_dir(root);
    let output = run_checked(runner, &command)?;
    let response: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
        UpdateError::message(format!(
            "latest_npm_version: {package} returned invalid JSON: {source}"
        ))
    })?;
    response
        .get("version")
        .and_then(Value::as_str)
        .filter(|version| !version.is_empty() && *version != "null")
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            UpdateError::message(format!(
                "latest_npm_version: {package} の latest version を取得できなかった"
            ))
        })
}

fn read_npm_package_json(archive_path: &Path, label: &str) -> Result<Vec<u8>, UpdateError> {
    const MAX_PACKAGE_JSON_BYTES: u64 = 4 * 1024 * 1024;

    let archive_file =
        File::open(archive_path).map_err(|source| UpdateError::io(archive_path, source))?;
    let decoder = GzDecoder::new(archive_file);
    let mut archive = tar::Archive::new(decoder);
    let entries = archive.entries().map_err(|source| {
        UpdateError::message(format!("{label}: failed to read npm tarball: {source}"))
    })?;
    let mut package_json = None;
    for entry in entries {
        let mut entry = entry.map_err(|source| {
            UpdateError::message(format!(
                "{label}: failed to read npm tarball entry: {source}"
            ))
        })?;
        let path = entry
            .path()
            .map_err(|source| {
                UpdateError::message(format!(
                    "{label}: failed to read npm tarball entry path: {source}"
                ))
            })?
            .into_owned();
        if path.as_os_str().is_empty()
            || path.is_absolute()
            || path
                .components()
                .any(|component| !matches!(component, Component::Normal(_)))
        {
            return Err(UpdateError::message(format!(
                "{label}: npm tarball contained unsafe path {}",
                path.display()
            )));
        }
        let entry_type = entry.header().entry_type();
        if entry_type.is_symlink() || entry_type.is_hard_link() {
            return Err(UpdateError::message(format!(
                "{label}: npm tarball contained unsupported link {}",
                path.display()
            )));
        }
        if !entry_type.is_file() && !entry_type.is_dir() {
            return Err(UpdateError::message(format!(
                "{label}: npm tarball contained unsupported entry {}",
                path.display()
            )));
        }
        if path == Path::new("package/package.json") {
            if package_json.is_some() {
                return Err(UpdateError::message(format!(
                    "{label}: npm tarball contained duplicate package/package.json entries"
                )));
            }
            let size = entry.size();
            if size > MAX_PACKAGE_JSON_BYTES {
                return Err(UpdateError::message(format!(
                    "{label}: package/package.json exceeded {MAX_PACKAGE_JSON_BYTES} bytes"
                )));
            }
            let mut bytes = Vec::new();
            entry.read_to_end(&mut bytes).map_err(|source| {
                UpdateError::message(format!(
                    "{label}: failed to read package/package.json: {source}"
                ))
            })?;
            package_json = Some(bytes);
        }
    }
    package_json.ok_or_else(|| {
        UpdateError::message(format!(
            "{label}: npm tarball did not contain package/package.json"
        ))
    })
}

fn require_regular_file(path: &Path, message: &str) -> Result<(), UpdateError> {
    let metadata =
        std::fs::symlink_metadata(path).map_err(|_| UpdateError::message(message.to_owned()))?;
    if metadata.is_file() && !metadata.file_type().is_symlink() {
        Ok(())
    } else {
        Err(UpdateError::message(message.to_owned()))
    }
}

fn validate_npm_identity(
    bytes: &[u8],
    expected_name: &str,
    expected_version: &str,
    label: &str,
) -> Result<(), UpdateError> {
    let document: Value = serde_json::from_slice(bytes)
        .map_err(|source| UpdateError::message(format!("{label}: invalid JSON: {source}")))?;
    let name = document
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let version = document
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if name != expected_name || version != expected_version {
        return Err(UpdateError::message(format!(
            "{label}: expected {expected_name}@{expected_version}, found {name}@{version}"
        )));
    }
    Ok(())
}

fn validate_npm_lock(
    bytes: &[u8],
    expected_name: &str,
    expected_version: &str,
    label: &str,
) -> Result<(), UpdateError> {
    validate_npm_identity(
        bytes,
        expected_name,
        expected_version,
        &format!("{label} package-lock.json"),
    )?;
    let document: Value = serde_json::from_slice(bytes).map_err(|source| {
        UpdateError::message(format!("{label} package-lock.json: invalid JSON: {source}"))
    })?;
    let root = document
        .get("packages")
        .and_then(Value::as_object)
        .and_then(|packages| packages.get(""))
        .and_then(Value::as_object)
        .ok_or_else(|| {
            UpdateError::message(format!(
                "{label} package-lock.json: missing packages[\"\"] object"
            ))
        })?;
    let name = root.get("name").and_then(Value::as_str).unwrap_or_default();
    let version = root
        .get("version")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if name != expected_name || version != expected_version {
        return Err(UpdateError::message(format!(
            "{label} package-lock.json root: expected {expected_name}@{expected_version}, found {name}@{version}"
        )));
    }
    Ok(())
}

fn update_paired_flake_input<R: CommandRunner>(
    input: &str,
    repository: &str,
    version: &str,
    flake: &[u8],
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<(), UpdateError> {
    let updated_flake = replace_paired_version(flake, repository, version)?;
    transaction.replace("flake.nix", &updated_flake)?;
    println!("{input}: updating flake input to v{version}");
    // Mutating commands are deliberately single-shot; bounded retry applies only to reads.
    let command = CommandSpec::new("nix")
        .args(["flake", "update", input])
        .current_dir(transaction.root());
    let output = run_checked(runner, &command)?;
    forward_output(&output.stdout, &output.stderr)
}

fn refresh_assets<R: CommandRunner>(
    pin: &mut PinDocument,
    repository: &str,
    tag: &str,
    version: &str,
    naming: AssetNaming,
    runner: &R,
    root: &Path,
) -> Result<(), UpdateError> {
    for system in pin.keys(&["assets"])? {
        let name = match naming {
            AssetNaming::NameField => pin.string(&["assets", &system, "name"])?.to_owned(),
            AssetNaming::WatchexecTarget => {
                let target = pin.string(&["assets", &system, "target"])?.to_owned();
                format!("watchexec-{version}-{target}.tar.xz")
            }
        };
        let url = format!("https://github.com/{repository}/releases/download/{tag}/{name}");
        let hash = prefetch(runner, root, &url, false)?;
        pin.set_string(&["assets", &system, "hash"], hash)?;
    }
    Ok(())
}

fn latest_tag<R: CommandRunner>(
    runner: &R,
    root: &Path,
    repository: &str,
) -> Result<String, UpdateError> {
    let tag = if runner.is_available(Path::new("gh")) {
        let command = CommandSpec::new("gh")
            .args([
                "api",
                &format!("repos/{repository}/releases/latest"),
                "--jq",
                ".tag_name",
            ])
            .current_dir(root);
        let output = run_checked(runner, &command)?;
        output.stdout_utf8(&command)?.trim().to_owned()
    } else {
        let url = format!("https://api.github.com/repos/{repository}/releases/latest");
        let command = CommandSpec::new("curl")
            .args(["-fsSL", &url])
            .current_dir(root);
        let output = run_checked(runner, &command)?;
        let response: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
            UpdateError::message(format!(
                "latest_tag: {repository} returned invalid JSON: {source}"
            ))
        })?;
        response
            .get("tag_name")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    if tag.is_empty() || tag == "null" {
        return Err(UpdateError::message(format!(
            "latest_tag: {repository} の latest release tag を取得できなかった"
        )));
    }
    Ok(tag)
}

fn load_pin<R: CommandRunner>(
    transaction: &Transaction<'_, R>,
    path: &str,
) -> Result<PinDocument, UpdateError> {
    PinDocument::parse(path, transaction.read(path)?)
}

fn write_pin<R: CommandRunner>(
    transaction: &mut Transaction<'_, R>,
    path: &str,
    pin: &PinDocument,
) -> Result<(), UpdateError> {
    if let Some(rendered) = pin.rendered()? {
        transaction.replace(path, &rendered)?;
    }
    Ok(())
}

fn paired_version(bytes: &[u8], repository: &str) -> Result<String, UpdateError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message("update-pins: flake.nix is not valid UTF-8"))?;
    let matches = paired_version_matches(text, repository);
    if matches.len() != 1 {
        return Err(UpdateError::message(format!(
            "update-pins: expected one tagged flake input URL for {repository}, found {}",
            matches.len()
        )));
    }
    Ok(matches[0].2.to_owned())
}

fn replace_paired_version(
    bytes: &[u8],
    repository: &str,
    version: &str,
) -> Result<Vec<u8>, UpdateError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message("update-pins: flake.nix is not valid UTF-8"))?;
    let matches = paired_version_matches(text, repository);
    if matches.len() != 1 {
        return Err(UpdateError::message(format!(
            "update-pins: expected one tagged flake input URL for {repository}, found {}",
            matches.len()
        )));
    }
    let (start, end, _) = matches[0];
    let mut updated = String::with_capacity(text.len() - (end - start) + version.len());
    updated.push_str(&text[..start]);
    updated.push_str(version);
    updated.push_str(&text[end..]);
    Ok(updated.into_bytes())
}

fn paired_version_matches<'a>(text: &'a str, repository: &str) -> Vec<(usize, usize, &'a str)> {
    let prefix = format!("url = \"github:{repository}/v");
    text.match_indices(&prefix)
        .filter_map(|(match_start, _)| {
            let version_start = match_start + prefix.len();
            let tail = &text[version_start..];
            let version_end = tail.find("\";")? + version_start;
            Some((
                version_start,
                version_end,
                &text[version_start..version_end],
            ))
        })
        .collect()
}

pub(crate) fn validate_release_version(label: &str, version: &str) -> Result<(), UpdateError> {
    if is_release_version(version) {
        Ok(())
    } else {
        Err(UpdateError::message(format!(
            "{label}: unsupported release version '{version}'"
        )))
    }
}

fn is_release_version(version: &str) -> bool {
    if version.len() > 128 {
        return false;
    }
    let (without_build, build) = match version.split_once('+') {
        Some((base, build)) if !build.is_empty() && !build.contains('+') => (base, Some(build)),
        Some(_) => return false,
        None => (version, None),
    };
    let (core, prerelease) = match without_build.split_once('-') {
        Some((core, prerelease)) if !prerelease.is_empty() => (core, Some(prerelease)),
        Some(_) => return false,
        None => (without_build, None),
    };
    let mut components = core.split('.');
    let valid_core = components.by_ref().all(|component| {
        !component.is_empty() && component.bytes().all(|byte| byte.is_ascii_digit())
    });
    let component_count = core.split('.').count();
    let valid_suffix = |suffix: &str| {
        suffix
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-'))
    };
    valid_core
        && component_count >= 2
        && prerelease.is_none_or(valid_suffix)
        && build.is_none_or(valid_suffix)
}

fn forward_output(stdout: &[u8], stderr: &[u8]) -> Result<(), UpdateError> {
    std::io::stdout()
        .write_all(stdout)
        .map_err(|source| UpdateError::io("<stdout>", source))?;
    std::io::stderr()
        .write_all(stderr)
        .map_err(|source| UpdateError::io("<stderr>", source))
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::fs::File;
    use std::path::{Path, PathBuf};

    use flate2::Compression;
    use flate2::write::GzEncoder;

    use super::{
        is_implemented, is_release_version, latest_tag, paired_version, read_npm_package_json,
        replace_paired_version, validate_npm_identity, validate_npm_lock,
    };
    use crate::cli::Target;
    use crate::command::{CommandOutput, CommandRunner, CommandSpec};
    use crate::error::UpdateError;

    struct RecordingRunner {
        available: bool,
        commands: RefCell<Vec<CommandSpec>>,
        output: CommandOutput,
    }

    impl CommandRunner for RecordingRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            self.commands.borrow_mut().push(command.clone());
            Ok(self.output.clone())
        }

        fn is_available(&self, _program: &Path) -> bool {
            self.available
        }
    }

    #[test]
    fn validates_only_safe_release_versions() {
        for version in ["1.2", "1.2.3", "1.2.3-rc.1", "1.2.3+build.4"] {
            assert!(is_release_version(version), "{version} should be valid");
        }
        for version in [
            "1",
            "v1.2.3",
            "1.2.3${builtins.readFile ./flake.nix}",
            "1.2.3/",
            "1..3",
            "1.2.3+",
        ] {
            assert!(!is_release_version(version), "{version} should be invalid");
        }
    }

    #[test]
    fn paired_flake_version_requires_exactly_one_match_and_preserves_bytes() {
        let original =
            b"inputs.demo = {\n  url = \"github:owner/repo/v1.2.3\";\n  flake = false;\n};\n";
        assert_eq!(
            paired_version(original, "owner/repo").expect("paired version"),
            "1.2.3"
        );
        assert_eq!(
            replace_paired_version(original, "owner/repo", "2.0.0").expect("replace version"),
            b"inputs.demo = {\n  url = \"github:owner/repo/v2.0.0\";\n  flake = false;\n};\n"
        );
        assert!(paired_version(b"{}\n", "owner/repo").is_err());
        let duplicate = [original.as_slice(), original.as_slice()].concat();
        assert!(paired_version(&duplicate, "owner/repo").is_err());
    }

    #[test]
    fn github_discovery_falls_back_to_curl_with_exact_argv() {
        let runner = RecordingRunner {
            available: false,
            commands: RefCell::new(Vec::new()),
            output: CommandOutput {
                status: Some(0),
                stdout: br#"{"tag_name":"v1.2.3"}"#.to_vec(),
                stderr: Vec::new(),
            },
        };

        assert_eq!(
            latest_tag(&runner, Path::new("/repo"), "owner/repo").expect("latest tag"),
            "v1.2.3"
        );
        assert_eq!(
            runner.commands.into_inner(),
            [CommandSpec::new("curl")
                .args([
                    "-fsSL",
                    "https://api.github.com/repos/owner/repo/releases/latest",
                ])
                .current_dir(PathBuf::from("/repo"))]
        );
    }

    #[test]
    fn implementation_boundary_excludes_partial_all_runs() {
        for target in [
            Target::Hcom,
            Target::AgentSlack,
            Target::AgentBrowser,
            Target::Watchexec,
            Target::Shellfirm,
            Target::Herdr,
            Target::Difit,
            Target::ClaudeCodeSettingsSchema,
            Target::CodexApp,
        ] {
            assert!(
                is_implemented(target),
                "{} should be implemented",
                target.name()
            );
        }
        assert!(
            !is_implemented(Target::All),
            "all should remain private and incomplete"
        );
    }

    #[test]
    fn reads_only_the_exact_npm_package_manifest() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let archive = directory.path().join("package.tgz");
        write_test_archive(
            &archive,
            &[
                ("package/", b"", false),
                (
                    "package/package.json",
                    br#"{"name":"difit","version":"1.2.3"}"#,
                    false,
                ),
                ("package/README.md", b"ignored", false),
            ],
        );

        assert_eq!(
            read_npm_package_json(&archive, "difit").expect("package manifest"),
            br#"{"name":"difit","version":"1.2.3"}"#
        );
    }

    #[test]
    fn rejects_unsafe_and_duplicate_npm_archive_entries_without_extracting() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let outside = directory.path().join("outside");
        std::fs::write(&outside, b"sentinel").expect("outside sentinel");
        let unsafe_archive = directory.path().join("unsafe.tgz");
        write_test_archive(
            &unsafe_archive,
            &[
                ("package/package.json", br#"{"name":"difit"}"#, false),
                ("../outside", b"overwritten", true),
            ],
        );
        assert!(read_npm_package_json(&unsafe_archive, "difit").is_err());
        assert_eq!(
            std::fs::read(&outside).expect("outside sentinel"),
            b"sentinel"
        );

        let duplicate_archive = directory.path().join("duplicate.tgz");
        write_test_archive(
            &duplicate_archive,
            &[
                ("package/package.json", b"first", false),
                ("package/package.json", b"second", false),
            ],
        );
        assert!(read_npm_package_json(&duplicate_archive, "difit").is_err());

        let link_archive = directory.path().join("link.tgz");
        write_link_archive(&link_archive);
        assert!(read_npm_package_json(&link_archive, "difit").is_err());
    }

    #[test]
    fn rejects_missing_corrupt_and_oversized_npm_manifests() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let missing = directory.path().join("missing.tgz");
        write_test_archive(&missing, &[("package/README.md", b"missing", false)]);
        assert!(read_npm_package_json(&missing, "difit").is_err());

        let corrupt = directory.path().join("corrupt.tgz");
        std::fs::write(&corrupt, b"not a gzip archive").expect("corrupt archive");
        assert!(read_npm_package_json(&corrupt, "difit").is_err());

        let oversized = directory.path().join("oversized-pax.tgz");
        write_pax_size_archive(&oversized);
        let error =
            read_npm_package_json(&oversized, "difit").expect_err("PAX size must be enforced");
        assert!(error.to_string().contains("exceeded 4194304 bytes"));

        let special = directory.path().join("special.tgz");
        write_special_archive(&special);
        let error =
            read_npm_package_json(&special, "difit").expect_err("FIFO entry must be rejected");
        assert!(error.to_string().contains("unsupported entry package/fifo"));
    }

    #[test]
    fn validates_npm_manifest_and_lock_identity() {
        let manifest = br#"{"name":"difit","version":"1.2.3"}"#;
        assert!(validate_npm_identity(manifest, "difit", "1.2.3", "manifest").is_ok());
        assert!(validate_npm_identity(manifest, "other", "1.2.3", "manifest").is_err());
        assert!(validate_npm_identity(manifest, "difit", "9.9.9", "manifest").is_err());

        let lock = br#"{
            "name":"difit",
            "version":"1.2.3",
            "packages":{"":{"name":"difit","version":"1.2.3"}}
        }"#;
        assert!(validate_npm_lock(lock, "difit", "1.2.3", "difit").is_ok());
        let wrong_root = br#"{
            "name":"difit",
            "version":"1.2.3",
            "packages":{"":{"name":"difit","version":"9.9.9"}}
        }"#;
        assert!(validate_npm_lock(wrong_root, "difit", "1.2.3", "difit").is_err());
    }

    fn write_test_archive(path: &Path, entries: &[(&str, &[u8], bool)]) {
        let file = File::create(path).expect("test archive");
        let encoder = GzEncoder::new(file, Compression::default());
        let mut archive = tar::Builder::new(encoder);
        for (path, contents, raw_path) in entries {
            let mut header = tar::Header::new_gnu();
            header.set_mode(0o644);
            header.set_size(contents.len() as u64);
            if path.ends_with('/') {
                header.set_entry_type(tar::EntryType::Directory);
            } else {
                header.set_entry_type(tar::EntryType::Regular);
            }
            if *raw_path {
                let bytes = path.as_bytes();
                assert!(bytes.len() < 100);
                header.as_mut_bytes()[..100].fill(0);
                header.as_mut_bytes()[..bytes.len()].copy_from_slice(bytes);
            } else {
                header.set_path(path).expect("safe test path");
            }
            header.set_cksum();
            archive
                .append(&header, *contents)
                .expect("append archive entry");
        }
        let encoder = archive.into_inner().expect("finish tar archive");
        encoder.finish().expect("finish gzip stream");
    }

    fn write_link_archive(path: &Path) {
        let file = File::create(path).expect("test archive");
        let encoder = GzEncoder::new(file, Compression::default());
        let mut archive = tar::Builder::new(encoder);
        let mut header = tar::Header::new_gnu();
        header.set_mode(0o777);
        header.set_size(0);
        header.set_entry_type(tar::EntryType::Symlink);
        header.set_path("package/link").expect("link path");
        header.set_link_name("../../outside").expect("link target");
        header.set_cksum();
        archive
            .append(&header, std::io::empty())
            .expect("append symlink");
        let encoder = archive.into_inner().expect("finish tar archive");
        encoder.finish().expect("finish gzip stream");
    }

    fn write_pax_size_archive(path: &Path) {
        let file = File::create(path).expect("test archive");
        let encoder = GzEncoder::new(file, Compression::default());
        let mut archive = tar::Builder::new(encoder);
        archive
            .append_pax_extensions([("size", b"4194305".as_slice())])
            .expect("PAX size extension");
        let mut header = tar::Header::new_ustar();
        header.set_mode(0o644);
        header.set_size(2);
        header.set_entry_type(tar::EntryType::Regular);
        header
            .set_path("package/package.json")
            .expect("manifest path");
        header.set_cksum();
        archive
            .append(&header, b"{}".as_slice())
            .expect("append manifest");
        let encoder = archive.into_inner().expect("finish tar archive");
        encoder.finish().expect("finish gzip stream");
    }

    fn write_special_archive(path: &Path) {
        let file = File::create(path).expect("test archive");
        let encoder = GzEncoder::new(file, Compression::default());
        let mut archive = tar::Builder::new(encoder);
        let mut header = tar::Header::new_gnu();
        header.set_mode(0o644);
        header.set_size(0);
        header.set_entry_type(tar::EntryType::fifo());
        header.set_path("package/fifo").expect("FIFO path");
        header.set_cksum();
        archive
            .append(&header, std::io::empty())
            .expect("append FIFO");
        let encoder = archive.into_inner().expect("finish tar archive");
        encoder.finish().expect("finish gzip stream");
    }
}
