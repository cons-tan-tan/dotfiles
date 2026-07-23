use std::fs::File;
use std::io::Read as _;
use std::path::{Component, Path};

use flate2::read::GzDecoder;
use serde_json::Value;

use crate::build::{compute_hash_via_failed_build, refresh_existing_hash_via_build};
use crate::cli::Target;
use crate::codex_app;
use crate::command::{CommandRunner, CommandSpec, run_checked};
use crate::error::UpdateError;
use crate::ledger::{FileState, Ledger, diff_target};
use crate::pins::PinDocument;
use crate::policy::{MAX_ASSET_JOBS_LIMIT, RunPolicy};
use crate::prefetch::{prefetch_hash as prefetch, prefetch_result};
use crate::registry::{AssetNaming, TargetKind, TargetSpec, target_spec};
use crate::transaction::Transaction;
use crate::upstream::{latest_npm_version, latest_tag, validate_release_version};

pub fn is_implemented(target: Target) -> bool {
    target_spec(target).is_some_and(|spec| spec.kind.is_implemented())
}

pub fn run_target<R: CommandRunner + Sync>(
    target: Target,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
    ledger: &mut Ledger,
) -> Result<(), UpdateError> {
    let Some(spec) = target_spec(target) else {
        return Err(UpdateError::message(format!(
            "update-pins: Rust updater for {} is not yet implemented",
            target.name()
        )));
    };
    let before = spec
        .managed_paths
        .iter()
        .map(|path| {
            transaction.read(path).map(|bytes| FileState {
                path,
                bytes: Some(bytes),
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let result = match spec.kind {
        TargetKind::PairedRelease {
            repository,
            pin,
            input,
        } => update_paired_release(spec, repository, pin, input, policy, runner, transaction),
        TargetKind::Release {
            repository,
            pin,
            asset_naming,
            source_hash,
        } => update_release(
            spec,
            ReleaseUpdate {
                repository,
                pin_path: pin,
                asset_naming,
                source_hash,
            },
            policy,
            runner,
            transaction,
        ),
        TargetKind::UrlHash { pin } => update_url_hash(spec, pin, policy, runner, transaction),
        TargetKind::Shellfirm {
            repository,
            pin,
            lock,
            package,
        } => crate::shellfirm::update(
            spec,
            repository,
            pin,
            lock,
            package,
            policy,
            runner,
            transaction,
        ),
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
            policy,
            runner,
            transaction,
        ),
        TargetKind::CodexApp { pin } => codex_app::update(spec, pin, policy, runner, transaction),
        TargetKind::Unimplemented => Err(UpdateError::message(format!(
            "update-pins: Rust updater for {} is not yet implemented",
            spec.name
        ))),
    };
    let after = spec
        .managed_paths
        .iter()
        .map(|path| {
            transaction.read(path).map(|bytes| FileState {
                path,
                bytes: Some(bytes),
            })
        })
        .collect::<Result<Vec<_>, _>>();
    match (result, after) {
        (result, Ok(after)) => {
            ledger.extend(diff_target(spec, &before, &after));
            result.map(|_| ())
        }
        (Ok(_), Err(observation)) => Err(observation),
        (Err(primary), Err(_observation)) => Err(primary),
    }
}

fn update_paired_release<R: CommandRunner + Sync>(
    spec: &TargetSpec,
    repository: &str,
    pin_path: &str,
    input: &str,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let tag = latest_tag(policy, runner, transaction.root(), repository)?;
    let Some(version) = tag.strip_prefix('v') else {
        return Err(UpdateError::message(format!(
            "{}: unsupported release tag '{tag}'",
            spec.name
        )));
    };
    validate_release_version(spec.name, version)?;

    let flake = transaction.read("flake.nix")?;
    let current = paired_version(&flake, repository)?;
    if version == current && !policy.force {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: prefetching candidate {version} (current {current})...",
        spec.name
    );
    let mut pin = load_pin(transaction, pin_path)?;
    refresh_assets(
        spec,
        pin_path,
        &mut pin,
        repository,
        &tag,
        version,
        AssetNaming::NameField,
        policy,
        runner,
        transaction.root(),
    )?;
    write_pin(transaction, pin_path, &pin)?;

    if version != current {
        update_paired_flake_input(input, repository, version, &flake, runner, transaction)?;
    }
    Ok(true)
}

struct ReleaseUpdate<'a> {
    repository: &'a str,
    pin_path: &'a str,
    asset_naming: AssetNaming,
    source_hash: bool,
}

fn update_release<R: CommandRunner + Sync>(
    spec: &TargetSpec,
    release: ReleaseUpdate<'_>,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let ReleaseUpdate {
        repository,
        pin_path,
        asset_naming,
        source_hash,
    } = release;
    let mut pin = load_pin(transaction, pin_path)?;
    let current = pin.string(&["version"])?.to_owned();
    let tag = latest_tag(policy, runner, transaction.root(), repository)?;
    let version = tag.strip_prefix('v').unwrap_or(&tag);
    validate_release_version(spec.name, version)?;
    if version == current && !policy.force {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: prefetching candidate {version} (current {current})...",
        spec.name
    );
    pin.set_string(&["version"], version)?;
    refresh_assets(
        spec,
        pin_path,
        &mut pin,
        repository,
        &tag,
        version,
        asset_naming,
        policy,
        runner,
        transaction.root(),
    )?;
    if source_hash {
        println!("{}: prefetching candidate source hash...", spec.name);
        let source_url =
            format!("https://github.com/{repository}/archive/refs/tags/v{version}.tar.gz");
        let hash = prefetch(
            &format!("{}: {pin_path}: srcHash", spec.name),
            policy,
            runner,
            transaction.root(),
            &source_url,
            true,
        )?;
        pin.set_string(&["srcHash"], hash)?;
    }
    write_pin(transaction, pin_path, &pin)?;
    Ok(true)
}

fn update_url_hash<R: CommandRunner>(
    spec: &TargetSpec,
    pin_path: &str,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let mut pin = load_pin(transaction, pin_path)?;
    let url = pin.string(&["url"])?.to_owned();
    let current = pin.string(&["hash"])?.to_owned();
    println!("{}: checking schema hash...", spec.name);
    let hash = prefetch(
        &format!("{}: {pin_path}: hash", spec.name),
        policy,
        runner,
        transaction.root(),
        &url,
        false,
    )?;
    if hash == current {
        println!("{}: up to date", spec.name);
        return Ok(false);
    }
    pin.set_string(&["hash"], hash)?;
    write_pin(transaction, pin_path, &pin)?;
    println!("{}: candidate schema hash differs", spec.name);
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
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let flake = transaction.read("flake.nix")?;
    let current_lock = transaction.read(lock_path)?;
    let mut pin = load_pin(transaction, pin_path)?;
    let current_source_hash = pin.string(&["srcHash"])?.to_owned();
    let current = paired_version(&flake, repository)?;
    let version = latest_npm_version(policy, runner, transaction.root(), npm_package)?;
    validate_release_version(spec.name, &version)?;
    if version == current && !policy.force {
        println!("{}: {current} (up to date)", spec.name);
        return Ok(false);
    }

    println!(
        "{}: prefetching candidate {version} (current {current})...",
        spec.name
    );
    let source_url =
        format!("https://registry.npmjs.org/{npm_package}/-/{npm_package}-{version}.tgz");
    let source = prefetch_result(
        &format!("{}: {pin_path}: srcHash", spec.name),
        policy,
        runner,
        transaction.root(),
        &source_url,
        false,
    )?;
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
    run_checked(runner, &npm)?;

    let generated_lock = package_dir.join("package-lock.json");
    require_regular_file(
        &generated_lock,
        &format!("{}: npm did not generate package-lock.json", spec.name),
    )?;
    let lock_bytes = std::fs::read(&generated_lock)
        .map_err(|source| UpdateError::io(&generated_lock, source))?;
    validate_npm_lock(&lock_bytes, npm_package, &version, spec.name)?;
    if version == current && source.hash == current_source_hash && lock_bytes == current_lock {
        let changed = refresh_existing_hash_via_build(
            spec.name,
            package,
            pin_path,
            "npmDepsHash",
            &mut pin,
            runner,
            transaction,
        )?;
        println!("{}: candidate source and lockfile are unchanged", spec.name);
        return Ok(changed);
    }
    transaction.write_if_changed(lock_path, &lock_bytes)?;

    pin.set_string(&["srcHash"], source.hash)?;
    pin.set_string(&["npmDepsHash"], "")?;
    write_pin(transaction, pin_path, &pin)?;
    if version != current {
        update_paired_flake_input(input, repository, &version, &flake, runner, transaction)?;
    }
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
    transaction.write_if_changed("flake.nix", &updated_flake)?;
    println!("{input}: preparing candidate flake input v{version}");
    // Mutating commands are deliberately single-shot; bounded retry applies only to reads.
    let command = CommandSpec::new("nix")
        .args(["flake", "update", input])
        .current_dir(transaction.root());
    run_checked(runner, &command).map(|_| ())
}

#[allow(clippy::too_many_arguments)]
fn refresh_assets<R: CommandRunner + Sync>(
    spec: &TargetSpec,
    pin_path: &str,
    pin: &mut PinDocument,
    repository: &str,
    tag: &str,
    version: &str,
    naming: AssetNaming,
    policy: RunPolicy,
    runner: &R,
    root: &Path,
) -> Result<(), UpdateError> {
    refresh_assets_with(
        spec,
        pin_path,
        pin,
        repository,
        tag,
        version,
        naming,
        policy.asset_jobs.max_jobs(),
        &|request| prefetch(&request.label, policy, runner, root, &request.url, false),
    )
}

struct AssetPrefetchRequest {
    ordinal: usize,
    system: String,
    label: String,
    url: String,
}

struct AssetPrefetchResult {
    ordinal: usize,
    system: String,
    hash: String,
}

enum AssetWorkerOutcome {
    Completed(Result<String, UpdateError>),
    Panicked,
}

#[allow(clippy::too_many_arguments)]
fn refresh_assets_with<F>(
    spec: &TargetSpec,
    pin_path: &str,
    pin: &mut PinDocument,
    repository: &str,
    tag: &str,
    version: &str,
    naming: AssetNaming,
    max_jobs: usize,
    worker: &F,
) -> Result<(), UpdateError>
where
    F: Fn(&AssetPrefetchRequest) -> Result<String, UpdateError> + Sync,
{
    let mut requests = Vec::new();
    for (ordinal, system) in pin.keys(&["assets"])?.into_iter().enumerate() {
        let name = match naming {
            AssetNaming::NameField => pin.string(&["assets", &system, "name"])?.to_owned(),
            AssetNaming::WatchexecTarget => {
                let target = pin.string(&["assets", &system, "target"])?.to_owned();
                format!("watchexec-{version}-{target}.tar.xz")
            }
        };
        let url = format!("https://github.com/{repository}/releases/download/{tag}/{name}");
        requests.push(AssetPrefetchRequest {
            ordinal,
            label: format!("{}: {pin_path}: assets.{system}.hash", spec.name),
            system,
            url,
        });
    }

    let results = run_asset_workers(spec, pin_path, &requests, max_jobs, worker)?;
    for result in results {
        pin.set_string(&["assets", &result.system, "hash"], result.hash)?;
    }
    Ok(())
}

fn run_asset_workers<F>(
    spec: &TargetSpec,
    pin_path: &str,
    requests: &[AssetPrefetchRequest],
    max_jobs: usize,
    worker: &F,
) -> Result<Vec<AssetPrefetchResult>, UpdateError>
where
    F: Fn(&AssetPrefetchRequest) -> Result<String, UpdateError> + Sync,
{
    let mut results = Vec::with_capacity(requests.len());
    for batch in requests.chunks(max_jobs.clamp(1, usize::from(MAX_ASSET_JOBS_LIMIT))) {
        let outcomes = std::thread::scope(|scope| {
            let handles = batch
                .iter()
                .map(|request| {
                    let handle = scope.spawn(move || worker(request));
                    (request, handle)
                })
                .collect::<Vec<_>>();
            handles
                .into_iter()
                .map(|(request, handle)| {
                    let outcome = match handle.join() {
                        Ok(result) => AssetWorkerOutcome::Completed(result),
                        Err(_) => AssetWorkerOutcome::Panicked,
                    };
                    (request, outcome)
                })
                .collect::<Vec<_>>()
        });

        let mut first_failure = None;
        for (request, outcome) in outcomes {
            match outcome {
                AssetWorkerOutcome::Completed(Ok(hash)) => results.push(AssetPrefetchResult {
                    ordinal: request.ordinal,
                    system: request.system.clone(),
                    hash,
                }),
                AssetWorkerOutcome::Completed(Err(error)) => {
                    if first_failure.is_none() {
                        first_failure = Some(error);
                    }
                }
                AssetWorkerOutcome::Panicked => {
                    if first_failure.is_none() {
                        first_failure = Some(UpdateError::message(format!(
                            "{}: {pin_path}: assets.{}.hash: prefetch worker panicked",
                            spec.name, request.system
                        )));
                    }
                }
            }
        }
        if let Some(error) = first_failure {
            return Err(error);
        }
    }
    results.sort_by_key(|result| result.ordinal);
    Ok(results)
}

pub(crate) fn load_pin<R: CommandRunner>(
    transaction: &Transaction<'_, R>,
    path: &str,
) -> Result<PinDocument, UpdateError> {
    PinDocument::parse(path, transaction.read(path)?)
}

pub(crate) fn write_pin<R: CommandRunner>(
    transaction: &mut Transaction<'_, R>,
    path: &str,
    pin: &PinDocument,
) -> Result<(), UpdateError> {
    if let Some(rendered) = pin.rendered()? {
        transaction.write_if_changed(path, &rendered)?;
    }
    Ok(())
}

pub(crate) fn paired_version(bytes: &[u8], repository: &str) -> Result<String, UpdateError> {
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

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::fs::File;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Condvar, Mutex, mpsc};
    use std::time::Duration;

    use flate2::Compression;
    use flate2::write::GzEncoder;

    use super::{
        is_implemented, paired_version, read_npm_package_json, refresh_assets_with,
        replace_paired_version, validate_npm_identity, validate_npm_lock,
    };
    use crate::cli::Target;
    use crate::command::{CommandOutput, CommandRunner, CommandSpec};
    use crate::error::UpdateError;
    use crate::policy::RunPolicy;
    use crate::registry::{AssetNaming, target_spec};
    use crate::upstream::latest_tag;

    struct RecordingRunner {
        available: bool,
        commands: RefCell<Vec<CommandSpec>>,
        output: CommandOutput,
    }

    impl CommandRunner for RecordingRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            self.commands.borrow_mut().push(command.clone());
            if command.program == "curl" {
                let output_index = command
                    .args
                    .iter()
                    .position(|argument| argument == "--output")
                    .expect("curl output argument");
                let path = PathBuf::from(&command.args[output_index + 1]);
                std::fs::write(&path, &self.output.stdout)
                    .map_err(|source| UpdateError::io(&path, source))?;
                return Ok(CommandOutput {
                    status: self.output.status,
                    stdout: b"200".to_vec(),
                    stderr: self.output.stderr.clone(),
                });
            }
            Ok(self.output.clone())
        }

        fn is_available(&self, _program: &Path) -> bool {
            self.available
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
            latest_tag(
                RunPolicy::default(),
                &runner,
                Path::new("/repo"),
                "owner/repo"
            )
            .expect("latest tag"),
            "v1.2.3"
        );
        let commands = runner.commands.into_inner();
        assert_eq!(commands.len(), 1);
        let command = &commands[0];
        assert_eq!(command.program, "curl");
        assert_eq!(command.cwd, Some(PathBuf::from("/repo")));
        assert_eq!(
            command.args[..13],
            [
                "-sS",
                "--location",
                "--proto",
                "=https",
                "--proto-redir",
                "=https",
                "--connect-timeout",
                "15",
                "--max-time",
                "110",
                "--max-filesize",
                "4194304",
                "--output",
            ]
        );
        assert!(Path::new(&command.args[13]).is_absolute());
        assert_eq!(
            command.args[14..],
            [
                "--write-out",
                "%{http_code}",
                "https://api.github.com/repos/owner/repo/releases/latest",
            ]
        );
    }

    #[test]
    fn all_is_engine_only_not_a_concrete_target() {
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
            "all should remain outside concrete target dispatch"
        );
    }

    #[test]
    fn asset_jobs_bound_concurrency_and_preserve_pin_bytes_after_reverse_completion() {
        let spec = target_spec(Target::Hcom).expect("hcom spec");
        let mut sequential_pin = asset_test_pin();
        let sequential_active = AtomicUsize::new(0);
        let sequential_max_active = AtomicUsize::new(0);
        let sequential_order = Mutex::new(Vec::new());
        refresh_assets_with(
            spec,
            "pin.json",
            &mut sequential_pin,
            "owner/repo",
            "v1.2.3",
            "1.2.3",
            AssetNaming::NameField,
            1,
            &|request| {
                let active = sequential_active.fetch_add(1, Ordering::SeqCst) + 1;
                sequential_max_active.fetch_max(active, Ordering::SeqCst);
                sequential_order
                    .lock()
                    .expect("sequential order lock")
                    .push(request.ordinal);
                sequential_active.fetch_sub(1, Ordering::SeqCst);
                Ok(asset_test_hash(request.ordinal))
            },
        )
        .expect("sequential refresh");
        assert_eq!(sequential_max_active.load(Ordering::SeqCst), 1);
        assert_eq!(
            *sequential_order.lock().expect("sequential order lock"),
            vec![0, 1, 2, 3]
        );
        let sequential_bytes = sequential_pin
            .rendered()
            .expect("render sequential pin")
            .expect("sequential pin changed");

        let gates = Arc::new(
            (0..4)
                .map(|_| (Mutex::new(false), Condvar::new()))
                .collect::<Vec<_>>(),
        );
        let active = Arc::new(AtomicUsize::new(0));
        let max_active = Arc::new(AtomicUsize::new(0));
        let completion_order = Arc::new(Mutex::new(Vec::new()));
        let (started_tx, started_rx) = mpsc::channel();
        let (completed_tx, completed_rx) = mpsc::channel();
        let worker_gates = Arc::clone(&gates);
        let worker_active = Arc::clone(&active);
        let worker_max_active = Arc::clone(&max_active);
        let worker_completion_order = Arc::clone(&completion_order);
        let refresh = std::thread::spawn(move || {
            let mut pin = asset_test_pin();
            let result = refresh_assets_with(
                spec,
                "pin.json",
                &mut pin,
                "owner/repo",
                "v1.2.3",
                "1.2.3",
                AssetNaming::NameField,
                2,
                &|request| {
                    let current = worker_active.fetch_add(1, Ordering::SeqCst) + 1;
                    worker_max_active.fetch_max(current, Ordering::SeqCst);
                    started_tx
                        .send(request.ordinal)
                        .expect("report worker start");
                    let (released, ready) = &worker_gates[request.ordinal];
                    let mut released = released.lock().expect("worker gate lock");
                    while !*released {
                        released = ready.wait(released).expect("wait for worker release");
                    }
                    worker_completion_order
                        .lock()
                        .expect("completion order lock")
                        .push(request.ordinal);
                    worker_active.fetch_sub(1, Ordering::SeqCst);
                    completed_tx
                        .send(request.ordinal)
                        .expect("report worker completion");
                    Ok(asset_test_hash(request.ordinal))
                },
            );
            (result, pin)
        });

        assert_started_batch(&started_rx, &[0, 1]);
        release_worker(&gates, 1);
        assert_eq!(
            completed_rx
                .recv_timeout(Duration::from_secs(2))
                .expect("second worker completes first"),
            1
        );
        release_worker(&gates, 0);
        assert_eq!(
            completed_rx
                .recv_timeout(Duration::from_secs(2))
                .expect("first worker completes second"),
            0
        );
        assert_started_batch(&started_rx, &[2, 3]);
        release_worker(&gates, 3);
        assert_eq!(
            completed_rx
                .recv_timeout(Duration::from_secs(2))
                .expect("fourth worker completes first"),
            3
        );
        release_worker(&gates, 2);
        assert_eq!(
            completed_rx
                .recv_timeout(Duration::from_secs(2))
                .expect("third worker completes second"),
            2
        );

        let (result, parallel_pin) = refresh.join().expect("refresh controller thread");
        result.expect("parallel refresh");
        assert_eq!(max_active.load(Ordering::SeqCst), 2);
        assert_eq!(
            *completion_order.lock().expect("completion order lock"),
            vec![1, 0, 3, 2]
        );
        let parallel_bytes = parallel_pin
            .rendered()
            .expect("render parallel pin")
            .expect("parallel pin changed");
        assert_eq!(parallel_bytes, sequential_bytes);
    }

    #[test]
    fn asset_batch_failure_or_panic_leaves_pin_unchanged_and_stops_new_batches() {
        let spec = target_spec(Target::Hcom).expect("hcom spec");
        let mut failed_pin = asset_test_pin();
        let failure_calls = Mutex::new(Vec::new());
        let completed_after_failure = AtomicUsize::new(0);
        let error = refresh_assets_with(
            spec,
            "pin.json",
            &mut failed_pin,
            "owner/repo",
            "v1.2.3",
            "1.2.3",
            AssetNaming::NameField,
            2,
            &|request| {
                failure_calls
                    .lock()
                    .expect("failure calls lock")
                    .push(request.ordinal);
                if request.ordinal == 0 {
                    Err(UpdateError::message("first asset failed"))
                } else {
                    completed_after_failure.fetch_add(1, Ordering::SeqCst);
                    Ok(asset_test_hash(request.ordinal))
                }
            },
        )
        .expect_err("asset failure");
        assert_eq!(error.to_string(), "first asset failed");
        let mut calls = failure_calls.into_inner().expect("failure calls");
        calls.sort_unstable();
        assert_eq!(calls, vec![0, 1]);
        assert_eq!(completed_after_failure.load(Ordering::SeqCst), 1);
        assert_eq!(
            failed_pin.rendered().expect("render failed pin"),
            None,
            "a failed batch must not apply successful sibling hashes"
        );

        let mut panicked_pin = asset_test_pin();
        let panic_calls = Mutex::new(Vec::new());
        let error = refresh_assets_with(
            spec,
            "pin.json",
            &mut panicked_pin,
            "owner/repo",
            "v1.2.3",
            "1.2.3",
            AssetNaming::NameField,
            2,
            &|request| {
                panic_calls
                    .lock()
                    .expect("panic calls lock")
                    .push(request.ordinal);
                if request.ordinal == 1 {
                    panic!("intentional asset worker panic");
                }
                Ok(asset_test_hash(request.ordinal))
            },
        )
        .expect_err("asset worker panic");
        assert_eq!(
            error.to_string(),
            "hcom: pin.json: assets.x86_64-darwin.hash: prefetch worker panicked"
        );
        let mut calls = panic_calls.into_inner().expect("panic calls");
        calls.sort_unstable();
        assert_eq!(calls, vec![0, 1]);
        assert_eq!(panicked_pin.rendered().expect("render panicked pin"), None);
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

    fn asset_test_pin() -> crate::pins::PinDocument {
        crate::pins::PinDocument::parse(
            "pin.json",
            br#"{
  "assets": {
    "aarch64-darwin": {"name": "asset-a", "hash": "old-a"},
    "x86_64-darwin": {"name": "asset-b", "hash": "old-b"},
    "aarch64-linux": {"name": "asset-c", "hash": "old-c"},
    "x86_64-linux": {"name": "asset-d", "hash": "old-d"}
  }
}
"#
            .to_vec(),
        )
        .expect("asset test pin")
    }

    fn asset_test_hash(ordinal: usize) -> String {
        format!("new-hash-{ordinal}")
    }

    fn assert_started_batch(receiver: &mpsc::Receiver<usize>, expected: &[usize]) {
        let mut started = expected
            .iter()
            .map(|_| {
                receiver
                    .recv_timeout(Duration::from_secs(2))
                    .expect("worker starts")
            })
            .collect::<Vec<_>>();
        started.sort_unstable();
        assert_eq!(started, expected);
    }

    fn release_worker(gates: &[(Mutex<bool>, Condvar)], ordinal: usize) {
        let (released, ready) = &gates[ordinal];
        *released.lock().expect("worker gate lock") = true;
        ready.notify_one();
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
