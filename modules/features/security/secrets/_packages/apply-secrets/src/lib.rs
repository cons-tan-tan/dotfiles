pub mod cli;
mod command;
mod error;
mod filesystem;
pub mod manifest;
pub mod renderer;

use std::env;
use std::ffi::OsString;
use std::io::Write;
use std::path::PathBuf;

pub use error::AppError;

#[derive(Debug)]
pub struct Config {
    pub root: PathBuf,
    pub manifest: PathBuf,
    pub home: PathBuf,
    pub sops_bin: PathBuf,
}

impl Config {
    pub fn from_env() -> Result<Self, AppError> {
        Ok(Self {
            root: required_path("APPLY_SECRETS_ROOT")?,
            manifest: required_path("APPLY_SECRETS_MANIFEST")?,
            home: required_path("HOME")?,
            sops_bin: required_path("APPLY_SECRETS_SOPS_BIN")?,
        })
    }
}

fn required_path(name: &'static str) -> Result<PathBuf, AppError> {
    env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or(AppError::MissingEnvironment(name))
}

pub fn execute(
    config: &Config,
    dry_run: bool,
    stdout: &mut dyn Write,
    stderr: &mut dyn Write,
) -> Result<(), AppError> {
    let entries = manifest::load_and_preflight(&config.manifest, &config.root, &config.home)?;

    if dry_run {
        for entry in &entries {
            writeln!(
                stdout,
                "apply-secrets: would write {} (mode {:03o})",
                entry.destination.display(),
                entry.mode
            )?;
        }
        return Ok(());
    }

    let mut decrypt_failures = 0usize;
    for entry in &entries {
        let rendered = match command::decrypt_and_render(&config.sops_bin, entry) {
            Ok(rendered) => rendered,
            Err(error) => {
                writeln!(
                    stderr,
                    "apply-secrets: decryption/rendering of {} failed \
                     (GPG key not imported, or malformed secret?); skipping: {error}",
                    entry.relative_source
                )?;
                decrypt_failures += 1;
                continue;
            }
        };

        filesystem::place(entry, &config.home, &rendered)?;
        writeln!(
            stdout,
            "apply-secrets: wrote {}",
            entry.destination.display()
        )?;
    }

    if decrypt_failures > 0 {
        writeln!(
            stderr,
            "apply-secrets: {decrypt_failures} file(s) skipped because decryption failed"
        )?;
    }

    Ok(())
}

pub fn args_without_program() -> impl Iterator<Item = OsString> {
    env::args_os().skip(1)
}
