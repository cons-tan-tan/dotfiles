use std::fs::File;
use std::io::{self, Read as _};
use std::path::{Component, Path};
use std::time::Duration;

use flate2::read::MultiGzDecoder;
use serde_json::Value;

use crate::build::{build_package_once, compute_candidate_dependency_hash};
use crate::cli::Target;
use crate::codex_app;
use crate::command::{CommandRunner, CommandSpec, run_checked_limited_with_timeout};
use crate::error::UpdateError;
use crate::ledger::{FileState, Ledger, diff_target};
use crate::pins::PinDocument;
use crate::policy::{MAX_ASSET_JOBS_LIMIT, RunPolicy};
use crate::prefetch::{
    ExpandedLimitReader, TarPreflightLimits, prefetch_hash as prefetch, prefetch_result,
    tar_preflight_limits,
};
use crate::registry::{
    AssetNaming, PairedSource, PublishedArtifact, PublishedNodePackageSpec, TargetKind, TargetSpec,
    target_spec,
};
use crate::transaction::Transaction;
use crate::upstream::{latest_npm_version, latest_tag, validate_release_version};

const MUTATING_COMMAND_OUTPUT_LIMIT: usize = 1024 * 1024;
const MUTATING_COMMAND_TIMEOUT: Duration = Duration::from_secs(15 * 60);
const MAX_PACKAGE_JSON_BYTES: u64 = 4 * 1024 * 1024;

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
        TargetKind::PairedRelease { pin, source } => {
            update_paired_release(spec, source, pin, policy, runner, transaction)
        }
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
            guard_manifest,
            guard_lock,
            package,
        } => crate::shellfirm::update(
            spec,
            repository,
            pin,
            lock,
            guard_manifest,
            guard_lock,
            package,
            policy,
            runner,
            transaction,
        ),
        TargetKind::PublishedNodePackage(package) => {
            update_published_node_package(spec, package, policy, runner, transaction)
        }
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
    source: PairedSource,
    pin_path: &str,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let repository = source.repository;
    let tag = latest_tag(policy, runner, transaction.root(), repository)?;
    let Some(version) = tag.strip_prefix('v') else {
        return Err(UpdateError::message(format!(
            "{}: unsupported release tag '{tag}'",
            spec.name
        )));
    };
    validate_release_version(spec.name, version)?;

    let authority = transaction.read(source.authority.source_path)?;
    let current = paired_input_version(
        &authority,
        source.authority.source_path,
        source.input,
        repository,
    )?;
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
        update_paired_input(source, version, &authority, runner, transaction)?;
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

fn update_published_node_package<R: CommandRunner>(
    spec: &TargetSpec,
    package: PublishedNodePackageSpec,
    policy: RunPolicy,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<bool, UpdateError> {
    let PublishedArtifact::NpmRegistryTarball {
        package: npm_package,
        source_hash_field,
    } = package.artifact;
    validate_unscoped_npm_package_name(spec.name, npm_package)?;
    let paired = package.dependencies.source();
    let pin_path = package.pin;
    let authority = transaction.read(paired.authority.source_path)?;
    let mut pin = load_pin(transaction, pin_path)?;
    let current = paired_input_version(
        &authority,
        paired.authority.source_path,
        paired.input,
        paired.repository,
    )?;
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
        &format!("{}: {pin_path}: {source_hash_field}", spec.name),
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
    let package_json = read_npm_package_json(&archive_path, spec.name)?;
    validate_npm_identity(
        &package_json,
        npm_package,
        &version,
        &format!("{} package.json", spec.name),
    )?;
    pin.set_string(&[source_hash_field], source.hash)?;
    if version != current {
        update_paired_input(paired, &version, &authority, runner, transaction)?;
    }
    let dependency_hash = compute_candidate_dependency_hash(
        spec.name,
        package.build,
        package.dependencies,
        &pin,
        runner,
        transaction,
    )?;
    pin.set_string(&[package.build.dependency_hash_field], &dependency_hash)?;
    write_pin(transaction, pin_path, &pin)?;
    build_package_once(spec.name, package.build.package_attr, runner, transaction)?;
    Ok(true)
}

fn read_npm_package_json(archive_path: &Path, label: &str) -> Result<Vec<u8>, UpdateError> {
    let archive_file =
        File::open(archive_path).map_err(|source| UpdateError::io(archive_path, source))?;
    let compressed_bytes = archive_file
        .metadata()
        .map_err(|source| UpdateError::io(archive_path, source))?
        .len();
    read_npm_package_json_with_limits(
        archive_path,
        label,
        archive_file,
        tar_preflight_limits(compressed_bytes),
    )
}

fn read_npm_package_json_with_limits(
    archive_path: &Path,
    label: &str,
    archive_file: File,
    limits: TarPreflightLimits,
) -> Result<Vec<u8>, UpdateError> {
    let decoder = MultiGzDecoder::new(archive_file);
    let decoder = ExpandedLimitReader::new(decoder, limits.max_expanded_bytes);
    let mut archive = tar::Archive::new(decoder);
    let entries = archive.entries().map_err(|source| {
        UpdateError::message(format!("{label}: failed to read npm tarball: {source}"))
    })?;
    let mut package_json = None;
    let mut entry_count = 0_u64;
    let mut expanded_bytes = 0_u64;
    for entry in entries {
        entry_count = entry_count.checked_add(1).ok_or_else(|| {
            UpdateError::message(format!("{label}: npm tarball entry count overflowed"))
        })?;
        if entry_count > limits.max_entries {
            return Err(UpdateError::message(format!(
                "{label}: npm tarball exceeded the {}-entry limit",
                limits.max_entries
            )));
        }
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
            || path.as_os_str().as_encoded_bytes().len() > limits.max_path_bytes
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
        let size = entry.size();
        if path == Path::new("package/package.json") {
            if package_json.is_some() {
                return Err(UpdateError::message(format!(
                    "{label}: npm tarball contained duplicate package/package.json entries"
                )));
            }
            if size > MAX_PACKAGE_JSON_BYTES {
                return Err(UpdateError::message(format!(
                    "{label}: package/package.json exceeded {MAX_PACKAGE_JSON_BYTES} bytes"
                )));
            }
        }
        expanded_bytes = expanded_bytes.checked_add(size).ok_or_else(|| {
            UpdateError::message(format!(
                "{label}: npm tarball expanded byte count overflowed"
            ))
        })?;
        if expanded_bytes > limits.max_expanded_bytes {
            return Err(UpdateError::message(format!(
                "{label}: npm tarball exceeded the {}-byte expanded limit",
                limits.max_expanded_bytes
            )));
        }
        if path == Path::new("package/package.json") {
            let mut bytes = Vec::new();
            entry.read_to_end(&mut bytes).map_err(|source| {
                UpdateError::message(format!(
                    "{label}: failed to read package/package.json: {source}"
                ))
            })?;
            package_json = Some(bytes);
        }
    }
    let mut decoder = archive.into_inner();
    io::copy(&mut decoder, &mut io::sink()).map_err(|source| {
        UpdateError::message(format!(
            "{label}: failed to finish reading npm tarball {}: {source}",
            archive_path.display()
        ))
    })?;
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

fn validate_unscoped_npm_package_name(label: &str, package: &str) -> Result<(), UpdateError> {
    if package.is_empty()
        || package.len() > 214
        || package.starts_with(['.', '_'])
        || !package.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_' | b'.')
        })
    {
        return Err(UpdateError::message(format!(
            "{label}: registry contains an unsafe or unsupported unscoped npm package name"
        )));
    }
    Ok(())
}

pub(crate) fn update_paired_input<R: CommandRunner>(
    source: PairedSource,
    version: &str,
    authority: &[u8],
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<(), UpdateError> {
    let input = source.input;
    let repository = source.repository;
    let authority_spec = source.authority;
    let updated_authority = replace_paired_input_version(
        authority,
        authority_spec.source_path,
        input,
        repository,
        version,
    )?;
    transaction.write_if_changed(authority_spec.source_path, &updated_authority)?;

    if let Some(generator) = authority_spec.generator {
        println!("{input}: regenerating candidate flake");
        let command = CommandSpec::new(generator.program)
            .args(generator.args.iter().copied())
            .current_dir(transaction.root());
        run_mutating_command_once(runner, &command)?;
    }

    let generated_flake = transaction.read(authority_spec.generated_flake_path)?;
    let generated_version = paired_input_version(
        &generated_flake,
        authority_spec.generated_flake_path,
        input,
        repository,
    )?;
    if generated_version != version {
        return Err(UpdateError::message(format!(
            "{}: generated input {input} has v{generated_version}, expected v{version}",
            authority_spec.generated_flake_path
        )));
    }

    println!("{input}: preparing candidate flake input v{version}");
    // Mutating commands are deliberately single-shot; bounded retry applies only to reads.
    let command = CommandSpec::new("nix")
        .args(["flake", "update", input])
        .current_dir(transaction.root());
    run_mutating_command_once(runner, &command)
}

pub(crate) fn run_mutating_command_once<R: CommandRunner>(
    runner: &R,
    command: &CommandSpec,
) -> Result<(), UpdateError> {
    run_checked_limited_with_timeout(
        runner,
        command,
        MUTATING_COMMAND_OUTPUT_LIMIT,
        MUTATING_COMMAND_OUTPUT_LIMIT,
        MUTATING_COMMAND_TIMEOUT,
    )
    .map(|_| ())
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

pub(crate) fn paired_input_version(
    bytes: &[u8],
    label: &str,
    input: &str,
    repository: &str,
) -> Result<String, UpdateError> {
    parse_paired_input(bytes, label, input, repository).map(|paired| paired.version.to_owned())
}

fn replace_paired_input_version(
    bytes: &[u8],
    label: &str,
    input: &str,
    repository: &str,
    version: &str,
) -> Result<Vec<u8>, UpdateError> {
    validate_release_version(&format!("{label}: input {input} candidate"), version)?;
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message(format!("{label}: expected UTF-8")))?;
    let paired = parse_paired_input(bytes, label, input, repository)?;
    let mut updated = String::with_capacity(
        text.len() - (paired.version_end - paired.version_start) + version.len(),
    );
    updated.push_str(&text[..paired.version_start]);
    updated.push_str(version);
    updated.push_str(&text[paired.version_end..]);
    Ok(updated.into_bytes())
}

#[derive(Clone, Copy, Debug)]
struct PairedVersionMatch<'a> {
    assignment_start: usize,
    version_start: usize,
    version_end: usize,
    version: &'a str,
}

fn parse_paired_input<'a>(
    bytes: &'a [u8],
    label: &str,
    input: &str,
    repository: &str,
) -> Result<PairedVersionMatch<'a>, UpdateError> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| UpdateError::message(format!("{label}: expected UTF-8")))?;
    let nested_marker = format!("{input} = {{");
    let flake_file_marker = format!("flake-file.inputs.{input} = {{");
    let normal_code = normal_code_mask(text);
    let brace_depths = normal_brace_depths(text, &normal_code);
    let root_input_blocks = normal_block_ranges(text, "inputs = {", &normal_code)
        .into_iter()
        .filter(|(start, _)| is_root_input_block(text, *start, &normal_code, &brace_depths))
        .collect::<Vec<_>>();
    let mut declarations = Vec::new();
    let mut line_offset = 0_usize;
    for line in text.split_inclusive('\n') {
        let line_without_newline = line.trim_end_matches(['\r', '\n']);
        let trimmed = line_without_newline.trim_start();
        let marker = if trimmed == nested_marker {
            Some((nested_marker.as_str(), true))
        } else if trimmed == flake_file_marker {
            Some((flake_file_marker.as_str(), false))
        } else {
            None
        };
        if let Some((marker, needs_root_input_block)) = marker {
            let declaration_start = line_offset + line_without_newline.len() - trimmed.len();
            if !normal_code[declaration_start] {
                line_offset += line.len();
                continue;
            }
            let brace_start = declaration_start + marker.len() - 1;
            let block_end = matching_brace_end(text, brace_start).ok_or_else(|| {
                UpdateError::message(format!(
                    "{label}: unterminated input declaration for {input}"
                ))
            })?;
            if needs_root_input_block
                && !root_input_blocks.iter().any(|(inputs_start, inputs_end)| {
                    declaration_start > *inputs_start
                        && block_end < *inputs_end
                        && brace_depths[declaration_start] == brace_depths[*inputs_start] + 1
                })
            {
                line_offset += line.len();
                continue;
            }
            declarations.push((declaration_start, block_end));
        }
        line_offset += line.len();
    }
    if declarations.len() != 1 {
        return Err(UpdateError::message(format!(
            "{label}: expected one input declaration for {input}, found {}",
            declarations.len()
        )));
    }

    let matches = paired_version_matches(text, repository);
    let (block_start, block_end) = declarations[0];
    let block_matches = matches
        .iter()
        .filter(|paired| {
            paired.version_start >= block_start
                && paired.version_end <= block_end
                && brace_depths[paired.assignment_start] == brace_depths[block_start] + 1
        })
        .copied()
        .collect::<Vec<_>>();
    if matches.len() != 1 || block_matches.len() != 1 {
        return Err(UpdateError::message(format!(
            "{label}: input {input} does not uniquely own github:{repository}"
        )));
    }
    let paired = block_matches[0];
    validate_release_version(&format!("{label}: input {input}"), paired.version)?;
    Ok(paired)
}

fn normal_brace_depths(text: &str, normal_code: &[bool]) -> Vec<usize> {
    let mut depths = vec![0; text.len()];
    let mut depth = 0_usize;
    for (index, byte) in text.bytes().enumerate() {
        depths[index] = depth;
        if normal_code[index] {
            match byte {
                b'{' => depth += 1,
                b'}' => depth = depth.saturating_sub(1),
                _ => {}
            }
        }
    }
    depths
}

fn is_root_input_block(
    text: &str,
    inputs_start: usize,
    normal_code: &[bool],
    brace_depths: &[usize],
) -> bool {
    match brace_depths[inputs_start] {
        // Unit fixtures may omit the enclosing root attrset while preserving
        // the exact root-level input declaration shape.
        0 => true,
        1 => {
            let Some(parent) = enclosing_open_brace(text, inputs_start, normal_code) else {
                return false;
            };
            text.bytes()
                .enumerate()
                .find(|(index, byte)| normal_code[*index] && !byte.is_ascii_whitespace())
                .is_some_and(|(first, _)| first == parent)
        }
        _ => false,
    }
}

fn enclosing_open_brace(text: &str, offset: usize, normal_code: &[bool]) -> Option<usize> {
    let mut stack = Vec::new();
    for (index, byte) in text.bytes().enumerate().take(offset) {
        if !normal_code[index] {
            continue;
        }
        match byte {
            b'{' => stack.push(index),
            b'}' => {
                stack.pop()?;
            }
            _ => {}
        }
    }
    stack.last().copied()
}

fn normal_block_ranges(text: &str, marker: &str, normal_code: &[bool]) -> Vec<(usize, usize)> {
    let mut ranges = Vec::new();
    let mut line_offset = 0_usize;
    for line in text.split_inclusive('\n') {
        let line_without_newline = line.trim_end_matches(['\r', '\n']);
        let trimmed = line_without_newline.trim_start();
        if trimmed == marker {
            let start = line_offset + line_without_newline.len() - trimmed.len();
            if normal_code[start] {
                let brace_start = start + marker.len() - 1;
                if let Some(end) = matching_brace_end(text, brace_start) {
                    ranges.push((start, end));
                }
            }
        }
        line_offset += line.len();
    }
    ranges
}

fn matching_brace_end(text: &str, brace_start: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut index = brace_start;
    let mut depth = 0_usize;
    let mut state = LexicalState::Normal;
    while index < bytes.len() {
        match state {
            LexicalState::Normal => match bytes[index] {
                b'{' => depth += 1,
                b'}' => {
                    depth = depth.checked_sub(1)?;
                    if depth == 0 {
                        return Some(index + 1);
                    }
                }
                b'"' => state = LexicalState::String,
                b'\'' if bytes.get(index + 1) == Some(&b'\'') => {
                    state = LexicalState::IndentedString;
                    index += 1;
                }
                b'#' => state = LexicalState::LineComment,
                b'/' if bytes.get(index + 1) == Some(&b'*') => {
                    state = LexicalState::BlockComment;
                    index += 1;
                }
                _ => {}
            },
            LexicalState::String => match bytes[index] {
                b'\\' => index += usize::from(index + 1 < bytes.len()),
                b'"' => state = LexicalState::Normal,
                _ => {}
            },
            LexicalState::IndentedString => {
                if let Some(length) = indented_string_escape_length(bytes, index) {
                    index += length - 1;
                } else if indented_string_pair(bytes, index) {
                    state = LexicalState::Normal;
                    index += 1;
                }
            }
            LexicalState::LineComment => {
                if bytes[index] == b'\n' {
                    state = LexicalState::Normal;
                }
            }
            LexicalState::BlockComment => {
                if bytes[index] == b'*' && bytes.get(index + 1) == Some(&b'/') {
                    state = LexicalState::Normal;
                    index += 1;
                }
            }
        }
        index += 1;
    }
    None
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum LexicalState {
    Normal,
    String,
    IndentedString,
    LineComment,
    BlockComment,
}

fn indented_string_pair(bytes: &[u8], index: usize) -> bool {
    bytes.get(index) == Some(&b'\'') && bytes.get(index + 1) == Some(&b'\'')
}

fn indented_string_escape_length(bytes: &[u8], index: usize) -> Option<usize> {
    if !indented_string_pair(bytes, index) {
        return None;
    }
    match bytes.get(index + 2) {
        Some(b'\'' | b'\\') => Some(3),
        Some(b'$') if bytes.get(index + 3) == Some(&b'{') => Some(2),
        _ => None,
    }
}

fn normal_code_mask(text: &str) -> Vec<bool> {
    let bytes = text.as_bytes();
    let mut normal = vec![false; bytes.len()];
    let mut index = 0_usize;
    let mut state = LexicalState::Normal;
    while index < bytes.len() {
        match state {
            LexicalState::Normal => {
                normal[index] = true;
                match bytes[index] {
                    b'"' => {
                        normal[index] = false;
                        state = LexicalState::String;
                    }
                    b'\'' if bytes.get(index + 1) == Some(&b'\'') => {
                        normal[index] = false;
                        normal[index + 1] = false;
                        state = LexicalState::IndentedString;
                        index += 1;
                    }
                    b'#' => {
                        normal[index] = false;
                        state = LexicalState::LineComment;
                    }
                    b'/' if bytes.get(index + 1) == Some(&b'*') => {
                        normal[index] = false;
                        normal[index + 1] = false;
                        state = LexicalState::BlockComment;
                        index += 1;
                    }
                    _ => {}
                }
            }
            LexicalState::String => match bytes[index] {
                b'\\' => index += usize::from(index + 1 < bytes.len()),
                b'"' => state = LexicalState::Normal,
                _ => {}
            },
            LexicalState::IndentedString => {
                if let Some(length) = indented_string_escape_length(bytes, index) {
                    index += length - 1;
                } else if indented_string_pair(bytes, index) {
                    state = LexicalState::Normal;
                    index += 1;
                }
            }
            LexicalState::LineComment => {
                if bytes[index] == b'\n' {
                    normal[index] = true;
                    state = LexicalState::Normal;
                }
            }
            LexicalState::BlockComment => {
                if bytes[index] == b'*' && bytes.get(index + 1) == Some(&b'/') {
                    state = LexicalState::Normal;
                    index += 1;
                }
            }
        }
        index += 1;
    }
    normal
}

fn paired_version_matches<'a>(text: &'a str, repository: &str) -> Vec<PairedVersionMatch<'a>> {
    let bytes = text.as_bytes();
    let prefix = format!("github:{repository}/v");
    let mut matches = Vec::new();
    let mut index = 0_usize;
    let mut state = LexicalState::Normal;
    let mut string_start = 0_usize;
    while index < bytes.len() {
        match state {
            LexicalState::Normal => match bytes[index] {
                b'"' => {
                    state = LexicalState::String;
                    string_start = index + 1;
                }
                b'\'' if bytes.get(index + 1) == Some(&b'\'') => {
                    state = LexicalState::IndentedString;
                    index += 1;
                }
                b'#' => state = LexicalState::LineComment,
                b'/' if bytes.get(index + 1) == Some(&b'*') => {
                    state = LexicalState::BlockComment;
                    index += 1;
                }
                _ => {}
            },
            LexicalState::String => match bytes[index] {
                b'\\' => index += usize::from(index + 1 < bytes.len()),
                b'"' => {
                    let contents = &text[string_start..index];
                    if let Some(version) = contents.strip_prefix(&prefix)
                        && !version.is_empty()
                        && let Some(assignment_start) =
                            url_assignment_start(text, string_start - 1, index)
                    {
                        matches.push(PairedVersionMatch {
                            assignment_start,
                            version_start: string_start + prefix.len(),
                            version_end: index,
                            version,
                        });
                    }
                    state = LexicalState::Normal;
                }
                _ => {}
            },
            LexicalState::IndentedString => {
                if let Some(length) = indented_string_escape_length(bytes, index) {
                    index += length - 1;
                } else if indented_string_pair(bytes, index) {
                    state = LexicalState::Normal;
                    index += 1;
                }
            }
            LexicalState::LineComment => {
                if bytes[index] == b'\n' {
                    state = LexicalState::Normal;
                }
            }
            LexicalState::BlockComment => {
                if bytes[index] == b'*' && bytes.get(index + 1) == Some(&b'/') {
                    state = LexicalState::Normal;
                    index += 1;
                }
            }
        }
        index += 1;
    }
    matches
}

fn url_assignment_start(text: &str, quote_start: usize, quote_end: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut after = quote_end + 1;
    while after < bytes.len() && bytes[after].is_ascii_whitespace() {
        after += 1;
    }
    if bytes.get(after) != Some(&b';') {
        return None;
    }

    let mut cursor = quote_start;
    while cursor > 0 && bytes[cursor - 1].is_ascii_whitespace() {
        cursor -= 1;
    }
    if cursor == 0 || bytes[cursor - 1] != b'=' {
        return None;
    }
    cursor -= 1;
    while cursor > 0 && bytes[cursor - 1].is_ascii_whitespace() {
        cursor -= 1;
    }
    if cursor < 3 || &bytes[cursor - 3..cursor] != b"url" {
        return None;
    }
    let attribute_start = cursor - 3;
    let mut before = attribute_start;
    while before > 0 && matches!(bytes[before - 1], b' ' | b'\t' | b'\r') {
        before -= 1;
    }
    if before > 0 && !matches!(bytes[before - 1], b'\n' | b'{' | b';') {
        return None;
    }
    Some(attribute_start)
}

#[cfg(test)]
mod tests {
    use std::cell::{Cell, RefCell};
    use std::fs::File;
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Condvar, Mutex, mpsc};
    use std::time::Duration;

    use flate2::Compression;
    use flate2::write::GzEncoder;
    use tempfile::TempDir;

    use super::{
        MUTATING_COMMAND_OUTPUT_LIMIT, MUTATING_COMMAND_TIMEOUT, is_implemented,
        paired_input_version, read_npm_package_json, read_npm_package_json_with_limits,
        refresh_assets_with, replace_paired_input_version, run_mutating_command_once, run_target,
        validate_npm_identity, validate_unscoped_npm_package_name,
    };
    use crate::cli::Target;
    use crate::command::{CommandOutput, CommandRunner, CommandSpec, SystemCommandRunner};
    use crate::error::UpdateError;
    use crate::ledger::Ledger;
    use crate::policy::RunPolicy;
    use crate::prefetch::TarPreflightLimits;
    use crate::registry::{AssetNaming, TARGET_SPECS, TargetKind, TargetSpec, target_spec};
    use crate::transaction::{Repository, Transaction};

    const CURRENT_VERSION: &str = "1.2.3";
    const CURRENT_HASH: &str = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const CURRENT_CODEX_URL: &str =
        "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-1.2.3.zip";
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

    struct BoundedOnlyRunner {
        calls: Cell<usize>,
        stdout_limit: Cell<usize>,
        stderr_limit: Cell<usize>,
        timeout: Cell<Duration>,
    }

    struct FutureLayoutRunner {
        failure: Option<&'static str>,
        commands: RefCell<Vec<CommandSpec>>,
    }

    impl CommandRunner for FutureLayoutRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            if command.program == Path::new("git") {
                SystemCommandRunner.run(command)
            } else {
                panic!("unexpected unbounded command {}", command.display());
            }
        }

        fn run_limited_with_timeout(
            &self,
            command: &CommandSpec,
            _stdout_limit: usize,
            _stderr_limit: usize,
            _timeout: Duration,
        ) -> Result<CommandOutput, UpdateError> {
            self.commands.borrow_mut().push(command.clone());
            let args = command
                .args
                .iter()
                .map(|argument| argument.to_string_lossy().into_owned())
                .collect::<Vec<_>>();
            let root = command.cwd.as_deref().expect("fixture command cwd");
            if args == ["run", ".#write-flake"] {
                if self.failure == Some("generator") {
                    std::fs::write(root.join("flake.nix"), b"partial generated flake\n")
                        .expect("partial generated flake");
                    return Ok(CommandOutput {
                        status: Some(1),
                        stdout: Vec::new(),
                        stderr: b"generator failed".to_vec(),
                    });
                }
                let module = std::fs::read(root.join("modules/features/example.nix"))
                    .expect("future authority module");
                let version = paired_input_version(
                    &module,
                    "modules/features/example.nix",
                    "example-src",
                    "owner/example",
                )
                .expect("future authority version");
                std::fs::write(
                    root.join("flake.nix"),
                    format!(
                        "inputs = {{\n  example-src = {{\n    url = \"github:owner/example/v{version}\";\n  }};\n}};\n"
                    ),
                )
                .expect("generated flake");
            } else if args == ["flake", "update", "example-src"] {
                if self.failure == Some("lock") {
                    std::fs::write(root.join("flake.lock"), b"partial lock\n")
                        .expect("partial lock");
                    return Ok(CommandOutput {
                        status: Some(1),
                        stdout: Vec::new(),
                        stderr: b"lock update failed".to_vec(),
                    });
                }
                std::fs::write(root.join("flake.lock"), b"candidate lock\n")
                    .expect("candidate lock");
            } else {
                panic!("unexpected future-layout command {}", command.display());
            }
            Ok(CommandOutput {
                status: Some(0),
                stdout: Vec::new(),
                stderr: Vec::new(),
            })
        }

        fn is_available(&self, _program: &Path) -> bool {
            false
        }
    }

    struct CurrentMetadataRunner {
        commands: Mutex<Vec<CommandSpec>>,
    }

    impl CurrentMetadataRunner {
        fn new() -> Self {
            Self {
                commands: Mutex::new(Vec::new()),
            }
        }

        fn take_programs(&self) -> Vec<String> {
            std::mem::take(&mut *self.commands.lock().expect("metadata commands lock"))
                .into_iter()
                .map(|command| command.program.to_string_lossy().into_owned())
                .collect()
        }
    }

    impl CommandRunner for CurrentMetadataRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            if command.program == "git" {
                return SystemCommandRunner.run(command);
            }

            self.commands
                .lock()
                .expect("metadata commands lock")
                .push(command.clone());
            if command.program == "gh" {
                return Ok(CommandOutput {
                    status: Some(0),
                    stdout: format!(
                        "HTTP/2.0 200 OK\r\ncontent-type: application/json\r\n\r\n{{\"tag_name\":\"v{CURRENT_VERSION}\"}}"
                    )
                    .into_bytes(),
                    stderr: Vec::new(),
                });
            }
            if command.program == "curl" {
                let output_index = command
                    .args
                    .iter()
                    .position(|argument| argument == "--output")
                    .expect("curl output argument");
                let output_path = PathBuf::from(&command.args[output_index + 1]);
                let url = command.args.last().expect("curl URL").to_string_lossy();
                let body = if url.ends_with("/difit/latest") {
                    format!("{{\"version\":\"{CURRENT_VERSION}\"}}")
                } else if url == crate::codex_app::APPCAST_URL {
                    format!(
                        "<rss><channel><item><title>{CURRENT_VERSION}</title><enclosure url=\"{CURRENT_CODEX_URL}\"/></item></channel></rss>"
                    )
                } else {
                    "{}".to_owned()
                };
                std::fs::write(&output_path, body)
                    .map_err(|source| UpdateError::io(&output_path, source))?;
                return Ok(CommandOutput {
                    status: Some(0),
                    stdout: b"200".to_vec(),
                    stderr: Vec::new(),
                });
            }
            if command.program == "nix" {
                return Ok(CommandOutput {
                    status: Some(0),
                    stdout: format!("{{\"hash\":\"{CURRENT_HASH}\"}}").into_bytes(),
                    stderr: Vec::new(),
                });
            }
            panic!("unexpected no-op command {}", command.display());
        }

        fn is_available(&self, program: &Path) -> bool {
            program == Path::new("gh")
        }
    }

    impl CommandRunner for BoundedOnlyRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            panic!("unexpected unbounded command {}", command.display());
        }

        fn run_limited_with_timeout(
            &self,
            _command: &CommandSpec,
            stdout_limit: usize,
            stderr_limit: usize,
            timeout: Duration,
        ) -> Result<CommandOutput, UpdateError> {
            self.calls.set(self.calls.get() + 1);
            self.stdout_limit.set(stdout_limit);
            self.stderr_limit.set(stderr_limit);
            self.timeout.set(timeout);
            Ok(CommandOutput {
                status: Some(0),
                stdout: Vec::new(),
                stderr: Vec::new(),
            })
        }

        fn is_available(&self, _program: &Path) -> bool {
            false
        }
    }

    #[test]
    fn mutating_commands_are_single_shot_and_explicitly_bounded() {
        let runner = BoundedOnlyRunner {
            calls: Cell::new(0),
            stdout_limit: Cell::new(0),
            stderr_limit: Cell::new(0),
            timeout: Cell::new(Duration::ZERO),
        };

        run_mutating_command_once(&runner, &CommandSpec::new("mutation"))
            .expect("bounded mutation");

        assert_eq!(runner.calls.get(), 1);
        assert_eq!(runner.stdout_limit.get(), MUTATING_COMMAND_OUTPUT_LIMIT);
        assert_eq!(runner.stderr_limit.get(), MUTATING_COMMAND_OUTPUT_LIMIT);
        assert_eq!(runner.timeout.get(), MUTATING_COMMAND_TIMEOUT);
    }

    fn future_layout_source() -> crate::registry::PairedSource {
        crate::registry::PairedSource {
            repository: "owner/example",
            input: "example-src",
            authority: crate::registry::InputAuthority {
                source_path: "modules/features/example.nix",
                generated_flake_path: "flake.nix",
                lock_path: "flake.lock",
                generator: Some(crate::registry::GeneratorCommand {
                    program: "nix",
                    args: &["run", ".#write-flake"],
                    baseline: None,
                }),
            },
        }
    }

    fn future_layout_repository() -> TempDir {
        let repository = TempDir::new().expect("future-layout repository");
        run_fixture_git(repository.path(), ["init", "-q"]);
        run_fixture_git(
            repository.path(),
            ["config", "user.email", "test@example.invalid"],
        );
        run_fixture_git(
            repository.path(),
            ["config", "user.name", "future layout test"],
        );
        run_fixture_git(repository.path(), ["config", "commit.gpgsign", "false"]);
        std::fs::create_dir_all(repository.path().join("modules/features"))
            .expect("future module directory");
        std::fs::write(
            repository.path().join("modules/features/example.nix"),
            b"{ ... }:\n{\n  flake-file.inputs.example-src = {\n    url = \"github:owner/example/v1.2.3\";\n  };\n}\n",
        )
        .expect("future authority");
        std::fs::write(
            repository.path().join("flake.nix"),
            b"inputs = {\n  example-src = {\n    url = \"github:owner/example/v1.2.3\";\n  };\n};\n",
        )
        .expect("future generated flake");
        std::fs::write(repository.path().join("flake.lock"), b"original lock\n")
            .expect("future lock");
        run_fixture_git(repository.path(), ["add", "."]);
        run_fixture_git(repository.path(), ["commit", "-q", "-m", "initial"]);
        repository
    }

    #[test]
    fn future_module_authority_generates_flake_then_updates_lock_in_one_transaction() {
        let repository = future_layout_repository();
        let source = future_layout_source();
        let runner = FutureLayoutRunner {
            failure: None,
            commands: RefCell::new(Vec::new()),
        };
        let repository_handle =
            Repository::discover_in(&SystemCommandRunner, repository.path()).expect("repository");
        let managed = [
            source.authority.source_path,
            source.authority.generated_flake_path,
            source.authority.lock_path,
        ];
        let mut transaction =
            Transaction::begin_scoped(repository_handle, &runner, managed).expect("transaction");
        let authority = transaction
            .read(source.authority.source_path)
            .expect("authority bytes");

        super::update_paired_input(source, "2.0.0", &authority, &runner, &mut transaction)
            .expect("future paired update");

        assert!(
            std::fs::read_to_string(repository.path().join("modules/features/example.nix"))
                .expect("updated authority")
                .contains("v2.0.0")
        );
        assert!(
            std::fs::read_to_string(repository.path().join("flake.nix"))
                .expect("updated generated flake")
                .contains("v2.0.0")
        );
        assert_eq!(
            std::fs::read(repository.path().join("flake.lock")).expect("updated lock"),
            b"candidate lock\n"
        );
        let commands = runner.commands.borrow();
        assert_eq!(commands.len(), 2);
        assert_eq!(commands[0].args, ["run", ".#write-flake"]);
        assert_eq!(commands[1].args, ["flake", "update", "example-src"]);
        drop(commands);
        transaction.rollback().expect("rollback future update");
        assert!(
            std::fs::read_to_string(repository.path().join("modules/features/example.nix"))
                .expect("restored authority")
                .contains("v1.2.3")
        );
        assert!(
            std::fs::read_to_string(repository.path().join("flake.nix"))
                .expect("restored generated flake")
                .contains("v1.2.3")
        );
        assert_eq!(
            std::fs::read(repository.path().join("flake.lock")).expect("restored lock"),
            b"original lock\n"
        );
    }

    #[test]
    fn future_module_authority_failures_restore_every_managed_file() {
        for failure in ["generator", "lock", "candidate"] {
            let repository = future_layout_repository();
            let source = future_layout_source();
            let runner = FutureLayoutRunner {
                failure: Some(failure),
                commands: RefCell::new(Vec::new()),
            };
            let repository_handle =
                Repository::discover_in(&SystemCommandRunner, repository.path())
                    .expect("repository");
            let managed = [
                source.authority.source_path,
                source.authority.generated_flake_path,
                source.authority.lock_path,
            ];
            let mut transaction = Transaction::begin_scoped(repository_handle, &runner, managed)
                .expect("transaction");
            let authority = transaction
                .read(source.authority.source_path)
                .expect("authority bytes");
            let result =
                super::update_paired_input(source, "2.0.0", &authority, &runner, &mut transaction)
                    .and_then(|()| {
                        if failure == "candidate" {
                            Err(UpdateError::message("candidate build failed"))
                        } else {
                            Ok(())
                        }
                    });
            assert!(result.is_err(), "{failure} failure must propagate");
            transaction
                .rollback()
                .expect("rollback failed future update");
            assert!(
                std::fs::read_to_string(repository.path().join("modules/features/example.nix"))
                    .expect("restored authority")
                    .contains("v1.2.3"),
                "{failure}: authority was not restored"
            );
            assert!(
                std::fs::read_to_string(repository.path().join("flake.nix"))
                    .expect("restored generated flake")
                    .contains("v1.2.3"),
                "{failure}: generated flake was not restored"
            );
            assert_eq!(
                std::fs::read(repository.path().join("flake.lock")).expect("restored lock"),
                b"original lock\n",
                "{failure}: lock was not restored"
            );
        }
    }

    #[test]
    fn paired_input_version_supports_current_and_flake_file_syntax() {
        let original = b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v1.2.3\";\n    flake = false;\n  };\n};\n";
        assert_eq!(
            paired_input_version(original, "flake.nix", "demo", "owner/repo")
                .expect("current input version"),
            "1.2.3"
        );
        assert_eq!(
            replace_paired_input_version(
                original,
                "flake.nix",
                "demo",
                "owner/repo",
                "2.0.0"
            )
            .expect("replace version"),
            b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v2.0.0\";\n    flake = false;\n  };\n};\n"
        );

        let module = b"# github:owner/repo/v0.0.0\r\nflake-file.inputs.demo = {\r\n  url = \"github:owner/repo/v1.2.3\";\r\n  note = \"{ braces in strings are ignored }\";\r\n};\r\n";
        let expected = b"# github:owner/repo/v0.0.0\r\nflake-file.inputs.demo = {\r\n  url = \"github:owner/repo/v2.0.0\";\r\n  note = \"{ braces in strings are ignored }\";\r\n};\r\n";
        assert_eq!(
            paired_input_version(module, "modules/features/demo.nix", "demo", "owner/repo")
                .expect("module input version"),
            "1.2.3"
        );
        assert_eq!(
            replace_paired_input_version(
                module,
                "modules/features/demo.nix",
                "demo",
                "owner/repo",
                "2.0.0"
            )
            .expect("replace module version"),
            expected
        );
    }

    #[test]
    fn paired_input_version_rejects_ambiguous_or_mismatched_declarations() {
        assert!(paired_input_version(b"{}\n", "source.nix", "demo", "owner/repo").is_err());
        let duplicate = b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v1.2.3\";\n  };\n  demo = {\n    url = \"github:owner/repo/v1.2.3\";\n  };\n};\n";
        assert!(paired_input_version(duplicate, "source.nix", "demo", "owner/repo").is_err());
        let wrong_repository = b"demo = {\n  url = \"github:someone/else/v1.2.3\";\n  note = \"github:owner/repo/v1.2.3\";\n};\n";
        assert!(
            paired_input_version(wrong_repository, "source.nix", "demo", "owner/repo").is_err()
        );
        let outside_inputs = b"demo = {\n  url = \"github:owner/repo/v1.2.3\";\n};\n";
        assert!(paired_input_version(outside_inputs, "flake.nix", "demo", "owner/repo").is_err());
        let globally_ambiguous = b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v1.2.3\";\n  };\n  other = {\n    url = \"github:owner/repo/v1.2.3\";\n  };\n};\n";
        assert!(
            paired_input_version(globally_ambiguous, "flake.nix", "demo", "owner/repo").is_err()
        );
        let unsafe_version = b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v1.2.3${builtins.readFile ./secret}\";\n  };\n};\n";
        assert!(paired_input_version(unsafe_version, "flake.nix", "demo", "owner/repo").is_err());
        let nested_input = b"inputs = {\n  other = {\n    demo = {\n      url = \"github:owner/repo/v1.2.3\";\n    };\n  };\n};\n";
        assert!(paired_input_version(nested_input, "flake.nix", "demo", "owner/repo").is_err());
        let nested_inputs = b"{\n  wrapper = {\n    inputs = {\n      demo = {\n        url = \"github:owner/repo/v1.2.3\";\n      };\n    };\n  };\n}\n";
        assert!(paired_input_version(nested_inputs, "flake.nix", "demo", "owner/repo").is_err());
        let nested_url =
            b"inputs = {\n  demo = {\n    metadata.url = \"github:owner/repo/v1.2.3\";\n  };\n};\n";
        assert!(paired_input_version(nested_url, "flake.nix", "demo", "owner/repo").is_err());
        let concatenated_url =
            b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v1.2.3\" + suffix;\n  };\n};\n";
        assert!(paired_input_version(concatenated_url, "flake.nix", "demo", "owner/repo").is_err());
        assert!(
            replace_paired_input_version(
                b"inputs = {\n  demo = {\n    url = \"github:owner/repo/v1.2.3\";\n  };\n};\n",
                "flake.nix",
                "demo",
                "owner/repo",
                "2.0.0${builtins.readFile ./secret}",
            )
            .is_err()
        );
    }

    #[test]
    fn paired_input_parser_ignores_comment_string_and_non_url_decoys() {
        let source = br#"
/*
demo = {
  url = "github:owner/repo/v0.0.1";
};
*/
{
  decoy = ''
''${IGNORED}
echo ''' escaped quote
demo = {
  url = "github:owner/repo/v0.0.2";
};
'';
  inputs = {
    demo = {
    # github:owner/repo/v0.0.3
    note = "github:owner/repo/v0.0.4";
    url = "github:owner/repo/v1.2.3";
    };
  };
}
"#;

        assert_eq!(
            paired_input_version(source, "source.nix", "demo", "owner/repo")
                .expect("real URL assignment"),
            "1.2.3"
        );
        let updated =
            replace_paired_input_version(source, "source.nix", "demo", "owner/repo", "2.0.0")
                .expect("replace real URL assignment");
        assert!(
            std::str::from_utf8(&updated)
                .expect("updated UTF-8")
                .contains("url = \"github:owner/repo/v2.0.0\";")
        );
        assert!(
            std::str::from_utf8(&updated)
                .expect("updated UTF-8")
                .contains("note = \"github:owner/repo/v0.0.4\";")
        );
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
    fn production_dispatch_is_stable_for_every_current_target() {
        for spec in TARGET_SPECS {
            let repository = current_target_repository(spec);
            let runner = CurrentMetadataRunner::new();
            let originals = spec
                .managed_paths
                .iter()
                .map(|relative| {
                    let path = repository.path().join(relative);
                    (
                        *relative,
                        std::fs::read(&path).expect("managed bytes"),
                        std::fs::metadata(&path)
                            .expect("managed metadata")
                            .permissions(),
                    )
                })
                .collect::<Vec<_>>();

            for attempt in 1..=2 {
                let repository_handle =
                    Repository::discover_in(&SystemCommandRunner, repository.path())
                        .expect("repository");
                let mut transaction =
                    Transaction::begin_scoped(repository_handle, &runner, spec.managed_paths)
                        .expect("transaction");
                let mut ledger = Ledger::default();

                run_target(
                    spec.target,
                    RunPolicy::default(),
                    &runner,
                    &mut transaction,
                    &mut ledger,
                )
                .unwrap_or_else(|error| {
                    panic!("{} no-op attempt {attempt} failed: {error}", spec.name)
                });

                assert!(
                    ledger.is_empty(),
                    "{} no-op attempt {attempt} recorded changes",
                    spec.name
                );
                for (relative, bytes, permissions) in &originals {
                    let path = repository.path().join(relative);
                    assert_eq!(
                        std::fs::read(&path).expect("stable managed bytes"),
                        *bytes,
                        "{} changed {relative} on no-op attempt {attempt}",
                        spec.name
                    );
                    assert_eq!(
                        std::fs::metadata(&path)
                            .expect("stable managed metadata")
                            .permissions(),
                        *permissions,
                        "{} changed {relative} mode on no-op attempt {attempt}",
                        spec.name
                    );
                }
                transaction.commit().expect("commit no-op transaction");
                assert_eq!(
                    runner.take_programs(),
                    expected_noop_programs(spec.kind),
                    "{} invoked an unexpected no-op child on attempt {attempt}",
                    spec.name
                );
            }
        }
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

    #[test]
    fn npm_archive_scan_enforces_entry_expansion_and_path_limits() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let manifest = br#"{"name":"difit","version":"1.2.3"}"#;

        let entries = directory.path().join("entries.tgz");
        write_test_archive(
            &entries,
            &[
                ("package/package.json", manifest, false),
                ("package/one", b"1", false),
                ("package/two", b"2", false),
            ],
        );
        let error = read_npm_package_json_with_limits(
            &entries,
            "difit",
            File::open(&entries).expect("entry archive"),
            TarPreflightLimits {
                max_entries: 2,
                max_expanded_bytes: 1024 * 1024,
                max_path_bytes: 4096,
            },
        )
        .expect_err("entry count must be bounded");
        assert!(error.to_string().contains("2-entry limit"));

        let expansion = directory.path().join("expansion.tgz");
        write_test_archive(
            &expansion,
            &[
                ("package/package.json", manifest, false),
                ("package/large", &[0; 256], false),
            ],
        );
        let error = read_npm_package_json_with_limits(
            &expansion,
            "difit",
            File::open(&expansion).expect("expansion archive"),
            TarPreflightLimits {
                max_entries: 10,
                max_expanded_bytes: 128,
                max_path_bytes: 4096,
            },
        )
        .expect_err("expanded bytes must be bounded");
        assert!(error.to_string().contains("128-byte expanded limit"));

        let path = directory.path().join("path.tgz");
        write_test_archive(
            &path,
            &[
                ("package/package.json", manifest, false),
                ("package/a-path-that-is-too-long", b"x", false),
            ],
        );
        let error = read_npm_package_json_with_limits(
            &path,
            "difit",
            File::open(&path).expect("path archive"),
            TarPreflightLimits {
                max_entries: 10,
                max_expanded_bytes: 1024 * 1024,
                max_path_bytes: 24,
            },
        )
        .expect_err("entry paths must be bounded");
        assert!(error.to_string().contains("unsafe path"));
    }

    fn current_target_repository(spec: &TargetSpec) -> TempDir {
        let repository = TempDir::new().expect("temporary current-target repository");
        run_fixture_git(repository.path(), ["init", "-q"]);
        run_fixture_git(
            repository.path(),
            ["config", "user.email", "test@example.invalid"],
        );
        run_fixture_git(
            repository.path(),
            ["config", "user.name", "update-pins no-op test"],
        );
        run_fixture_git(repository.path(), ["config", "commit.gpgsign", "false"]);
        for relative in spec.managed_paths {
            let path = repository.path().join(relative);
            std::fs::create_dir_all(path.parent().expect("managed path parent"))
                .expect("managed path parent directory");
            std::fs::write(&path, current_managed_contents(spec, relative))
                .expect("current managed contents");
        }
        run_fixture_git(repository.path(), ["add", "."]);
        run_fixture_git(repository.path(), ["commit", "-q", "-m", "initial"]);
        repository
    }

    fn current_managed_contents(spec: &TargetSpec, relative: &str) -> Vec<u8> {
        let contents = match spec.kind {
            TargetKind::PairedRelease { pin, source } => {
                if relative == pin {
                    "{}\n".to_owned()
                } else if relative == source.authority.source_path {
                    format!(
                        "inputs = {{\n  {} = {{\n    url = \"github:{}/v{CURRENT_VERSION}\";\n  }};\n}};\n",
                        source.input, source.repository
                    )
                } else {
                    "{}\n".to_owned()
                }
            }
            TargetKind::Release { pin, .. } => {
                assert_eq!(relative, pin);
                format!("{{\"version\":\"{CURRENT_VERSION}\"}}\n")
            }
            TargetKind::UrlHash { pin } => {
                assert_eq!(relative, pin);
                format!(
                    "{{\"url\":\"https://example.invalid/schema.json\",\"hash\":\"{CURRENT_HASH}\"}}\n"
                )
            }
            TargetKind::Shellfirm {
                pin,
                lock,
                guard_manifest,
                guard_lock,
                ..
            } => {
                if relative == pin {
                    format!(
                        "{{\"version\":\"{CURRENT_VERSION}\",\"srcHash\":\"{CURRENT_HASH}\"}}\n"
                    )
                } else if relative == lock {
                    "version = 4\n".to_owned()
                } else if relative == guard_manifest {
                    format!(
                        "[dependencies]\nshellfirm = {{ version = \"={CURRENT_VERSION}\", default-features = false }}\n"
                    )
                } else if relative == guard_lock {
                    format!(
                        "version = 4\n\n[[package]]\nname = \"agent-command-guard\"\nversion = \"0.1.0\"\ndependencies = [\n \"shellfirm\",\n]\n\n[[package]]\nname = \"shellfirm\"\nversion = \"{CURRENT_VERSION}\"\nsource = \"registry+https://github.com/rust-lang/crates.io-index\"\nchecksum = \"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"\n"
                    )
                } else {
                    panic!("unexpected Shellfirm managed path {relative}");
                }
            }
            TargetKind::PublishedNodePackage(package) => {
                if relative == package.pin {
                    "{}\n".to_owned()
                } else if relative == package.dependencies.source().authority.source_path {
                    let source = package.dependencies.source();
                    format!(
                        "inputs = {{\n  {} = {{\n    url = \"github:{}/v{CURRENT_VERSION}\";\n  }};\n}};\n",
                        source.input, source.repository
                    )
                } else {
                    "{}\n".to_owned()
                }
            }
            TargetKind::CodexApp { pin } => {
                assert_eq!(relative, pin);
                format!(
                    "{{\"appcast\":\"{}\",\"version\":\"{CURRENT_VERSION}\",\"url\":\"{CURRENT_CODEX_URL}\",\"hash\":\"{CURRENT_HASH}\",\"appName\":\"ChatGPT.app\",\"bundleIdentifier\":\"com.openai.codex\",\"displayName\":\"ChatGPT\"}}\n",
                    crate::codex_app::APPCAST_URL
                )
            }
            TargetKind::Unimplemented => panic!("{} is not implemented", spec.name),
        };
        contents.into_bytes()
    }

    fn expected_noop_programs(kind: TargetKind) -> Vec<String> {
        match kind {
            TargetKind::PairedRelease { .. }
            | TargetKind::Release { .. }
            | TargetKind::Shellfirm { .. } => vec!["gh".to_owned()],
            TargetKind::PublishedNodePackage(_) | TargetKind::CodexApp { .. } => {
                vec!["curl".to_owned()]
            }
            TargetKind::UrlHash { .. } => vec!["curl".to_owned(), "nix".to_owned()],
            TargetKind::Unimplemented => Vec::new(),
        }
    }

    fn run_fixture_git<const N: usize>(directory: &Path, arguments: [&str; N]) {
        let status = Command::new("git")
            .args(arguments)
            .current_dir(directory)
            .status()
            .expect("run fixture git");
        assert!(status.success(), "fixture git command failed");
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
    fn validates_npm_manifest_identity_and_registry_package_name() {
        let manifest = br#"{"name":"difit","version":"1.2.3"}"#;
        assert!(validate_npm_identity(manifest, "difit", "1.2.3", "manifest").is_ok());
        assert!(validate_npm_identity(manifest, "other", "1.2.3", "manifest").is_err());
        assert!(validate_npm_identity(manifest, "difit", "9.9.9", "manifest").is_err());
        assert!(validate_unscoped_npm_package_name("difit", "difit").is_ok());
        for invalid in [
            "",
            ".hidden",
            "_private",
            "@scope/difit",
            "Difit",
            "difit;bad",
        ] {
            assert!(validate_unscoped_npm_package_name("difit", invalid).is_err());
        }
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
