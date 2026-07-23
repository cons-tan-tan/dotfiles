use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::command::{CommandRunner, CommandSpec, run_checked};
use crate::error::UpdateError;

pub struct PrefetchResult {
    pub hash: String,
    pub store_path: Option<PathBuf>,
}

pub fn prefetch_hash<R: CommandRunner>(
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<String, UpdateError> {
    Ok(prefetch_result(runner, root, url, unpack)?.hash)
}

pub fn prefetch_result<R: CommandRunner>(
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
    let output = run_checked(runner, &command)?;
    let response: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
        UpdateError::message(format!(
            "prefetch returned invalid JSON for {url}: {source}"
        ))
    })?;
    let hash = response
        .get("hash")
        .and_then(Value::as_str)
        .filter(|hash| !hash.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| UpdateError::message(format!("prefetch did not return a hash for {url}")))?;
    let store_path = response
        .get("storePath")
        .and_then(Value::as_str)
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);
    Ok(PrefetchResult { hash, store_path })
}
