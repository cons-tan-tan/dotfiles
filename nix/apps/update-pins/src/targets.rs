use std::io::Write as _;
use std::path::Path;

use serde_json::Value;

use crate::cli::Target;
use crate::command::{CommandRunner, CommandSpec, run_checked};
use crate::error::UpdateError;
use crate::pins::PinDocument;
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

    let updated_flake = replace_paired_version(&flake, repository, version)?;
    transaction.replace("flake.nix", &updated_flake)?;
    println!("{input}: updating flake input to v{version}");
    let command = CommandSpec::new("nix")
        .args(["flake", "update", input])
        .current_dir(transaction.root());
    let output = run_checked(runner, &command)?;
    forward_output(&output.stdout, &output.stderr)?;
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

fn prefetch<R: CommandRunner>(
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<String, UpdateError> {
    let mut command = CommandSpec::new("nix")
        .args(["store", "prefetch-file", "--json"])
        .current_dir(root);
    if unpack {
        command = command.arg("--unpack");
    }
    command = command.arg(url);
    let output = run_checked(runner, &command)?;
    let response: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
        UpdateError::message(format!(
            "prefetch returned invalid JSON for {url}: {source}"
        ))
    })?;
    response
        .get("hash")
        .and_then(Value::as_str)
        .filter(|hash| !hash.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| UpdateError::message(format!("prefetch did not return a hash for {url}")))
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

fn validate_release_version(label: &str, version: &str) -> Result<(), UpdateError> {
    if is_release_version(version) {
        Ok(())
    } else {
        Err(UpdateError::message(format!(
            "{label}: unsupported release version '{version}'"
        )))
    }
}

fn is_release_version(version: &str) -> bool {
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
    use std::path::{Path, PathBuf};

    use super::{
        is_implemented, is_release_version, latest_tag, paired_version, replace_paired_version,
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
            Target::Herdr,
            Target::ClaudeCodeSettingsSchema,
        ] {
            assert!(
                is_implemented(target),
                "{} should be implemented",
                target.name()
            );
        }
        for target in [
            Target::All,
            Target::Shellfirm,
            Target::Difit,
            Target::CodexApp,
        ] {
            assert!(
                !is_implemented(target),
                "{} should remain private and incomplete",
                target.name()
            );
        }
    }
}
