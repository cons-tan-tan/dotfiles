use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::command::{CommandRunner, CommandSpec, run_checked};
use crate::error::UpdateError;
use crate::validation::validate_sri_hash;

pub struct PrefetchResult {
    pub hash: String,
    pub store_path: Option<PathBuf>,
}

pub fn prefetch_hash<R: CommandRunner>(
    label: &str,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<String, UpdateError> {
    Ok(prefetch_result(label, runner, root, url, unpack)?.hash)
}

pub fn prefetch_result<R: CommandRunner>(
    label: &str,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<PrefetchResult, UpdateError> {
    let mut command = CommandSpec::new("nix")
        .args(["store", "prefetch-file", "--json"])
        .current_dir(root);
    if unpack {
        command = command.arg("--unpack");
    }
    command = command.arg(url);
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
