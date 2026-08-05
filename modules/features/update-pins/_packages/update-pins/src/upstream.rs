use std::path::Path;

use serde_json::Value;

use crate::command::CommandRunner;
use crate::error::UpdateError;
use crate::fetch::{download_bytes, gh_api_bytes};
use crate::policy::RunPolicy;

const GITHUB_RELEASE_MAX_BYTES: usize = 4 * 1024 * 1024;
const NPM_LATEST_MAX_BYTES: usize = 1024 * 1024;

pub(crate) fn latest_tag<R: CommandRunner>(
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    repository: &str,
) -> Result<String, UpdateError> {
    let bytes = if runner.is_available(Path::new("gh")) {
        gh_api_bytes(
            policy.retry,
            runner,
            root,
            repository,
            "GitHub latest release",
            &format!("repos/{repository}/releases/latest"),
            GITHUB_RELEASE_MAX_BYTES,
        )?
    } else {
        let url = github_latest_release_url(repository);
        download_bytes(
            policy.retry,
            runner,
            root,
            repository,
            "GitHub latest release",
            &url,
            GITHUB_RELEASE_MAX_BYTES,
        )?
    };
    parse_latest_release_tag(&bytes, repository)
}

pub(crate) fn latest_npm_version<R: CommandRunner>(
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    package: &str,
) -> Result<String, UpdateError> {
    let url = npm_latest_url(package);
    let bytes = download_bytes(
        policy.retry,
        runner,
        root,
        package,
        "npm latest metadata",
        &url,
        NPM_LATEST_MAX_BYTES,
    )?;
    parse_npm_latest_version(&bytes, package)
}

pub(crate) fn parse_latest_release_tag(
    bytes: &[u8],
    repository: &str,
) -> Result<String, UpdateError> {
    let response: Value = serde_json::from_slice(bytes).map_err(|source| {
        UpdateError::message(format!(
            "latest_tag: {repository} returned invalid JSON: {source}"
        ))
    })?;
    response
        .get("tag_name")
        .and_then(Value::as_str)
        .filter(|tag| !tag.is_empty() && *tag != "null")
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            UpdateError::message(format!(
                "latest_tag: {repository} did not return a latest release tag"
            ))
        })
}

pub(crate) fn parse_npm_latest_version(bytes: &[u8], package: &str) -> Result<String, UpdateError> {
    let response: Value = serde_json::from_slice(bytes).map_err(|source| {
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
                "latest_npm_version: {package} did not return a latest version"
            ))
        })
}

pub(crate) fn github_latest_release_url(repository: &str) -> String {
    format!("https://api.github.com/repos/{repository}/releases/latest")
}

pub(crate) fn npm_latest_url(package: &str) -> String {
    format!("https://registry.npmjs.org/{package}/latest")
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
    let valid_core = core.split('.').all(|component| {
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

#[cfg(test)]
mod tests {
    use super::{is_release_version, parse_latest_release_tag, parse_npm_latest_version};

    #[test]
    fn parses_latest_metadata_without_accepting_empty_or_wrong_typed_fields() {
        assert_eq!(
            parse_latest_release_tag(br#"{"tag_name":"v1.2.3"}"#, "owner/repo")
                .expect("GitHub tag"),
            "v1.2.3"
        );
        assert_eq!(
            parse_npm_latest_version(br#"{"version":"1.2.3"}"#, "demo").expect("npm version"),
            "1.2.3"
        );
        for invalid in [
            br#"{}"#.as_slice(),
            br#"{"tag_name":""}"#.as_slice(),
            br#"{"tag_name":1}"#.as_slice(),
        ] {
            assert!(parse_latest_release_tag(invalid, "owner/repo").is_err());
        }
        for invalid in [
            br#"{}"#.as_slice(),
            br#"{"version":""}"#.as_slice(),
            br#"{"version":1}"#.as_slice(),
        ] {
            assert!(parse_npm_latest_version(invalid, "demo").is_err());
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
}
