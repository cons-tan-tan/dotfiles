use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::command::{CommandRunner, CommandSpec, run_checked};
use crate::error::UpdateError;
use crate::fetch::download;
use crate::policy::RunPolicy;
use crate::validation::validate_sri_hash;

pub struct PrefetchResult {
    pub hash: String,
    pub store_path: Option<PathBuf>,
}

pub fn prefetch_hash<R: CommandRunner>(
    label: &str,
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<String, UpdateError> {
    Ok(prefetch_result(label, policy, runner, root, url, unpack)?.hash)
}

pub fn prefetch_result<R: CommandRunner>(
    label: &str,
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<PrefetchResult, UpdateError> {
    let downloaded = download(
        policy.retry,
        runner,
        root,
        label.split(':').next().unwrap_or("update-pins"),
        "artifact download",
        url,
    )?;
    let local_url = local_file_url(downloaded.path())?;
    let store_name = deterministic_store_name(url);
    let mut command = CommandSpec::new("nix")
        .args(["store", "prefetch-file", "--json", "--name", &store_name])
        .current_dir(root);
    if unpack {
        command = command.arg("--unpack");
    }
    command = command.arg(&local_url);
    let output = run_checked(runner, &command)
        .map_err(|error| UpdateError::message(format!("{label}: {error}")))?;
    let response: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
        UpdateError::message(format!("{label}: prefetch returned invalid JSON: {source}"))
    })?;
    let hash = response
        .get("hash")
        .and_then(Value::as_str)
        .filter(|hash| !hash.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| UpdateError::message(format!("{label}: prefetch did not return a hash")))?;
    validate_sri_hash(label, &hash)?;
    let store_path = response
        .get("storePath")
        .and_then(Value::as_str)
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);
    Ok(PrefetchResult { hash, store_path })
}

fn local_file_url(path: &Path) -> Result<String, UpdateError> {
    if !path.is_absolute() {
        return Err(UpdateError::message(format!(
            "prefetch temporary path is not absolute: {}",
            path.display()
        )));
    }
    let bytes = path.as_os_str().as_encoded_bytes();
    let mut url = String::from("file://");
    for &byte in bytes {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'-' | b'.' | b'_' | b'~') {
            url.push(char::from(byte));
        } else {
            use std::fmt::Write as _;
            write!(url, "%{byte:02X}").expect("writing to a String cannot fail");
        }
    }
    Ok(url)
}

fn deterministic_store_name(url: &str) -> String {
    let basename = url
        .split(['?', '#'])
        .next()
        .and_then(|path| path.rsplit('/').next())
        .filter(|basename| !basename.is_empty())
        .unwrap_or("download");
    let sanitized = basename
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '+' | '-' | '.' | '_') {
                character
            } else {
                '-'
            }
        })
        .take(96)
        .collect::<String>();
    format!("update-pins-{sanitized}")
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::{deterministic_store_name, local_file_url};

    #[test]
    fn local_file_url_percent_encodes_reserved_path_bytes() {
        assert_eq!(
            local_file_url(Path::new("/tmp/update pins/#asset%.zip")).expect("absolute UTF-8 path"),
            "file:///tmp/update%20pins/%23asset%25.zip"
        );
        assert!(local_file_url(Path::new("relative")).is_err());
    }

    #[test]
    fn store_name_is_deterministic_and_url_independent() {
        assert_eq!(
            deterministic_store_name("https://example.com/releases/tool-v1.tar.gz?token=hidden"),
            "update-pins-tool-v1.tar.gz"
        );
        assert_eq!(
            deterministic_store_name("https://example.com/"),
            "update-pins-download"
        );
    }
}
