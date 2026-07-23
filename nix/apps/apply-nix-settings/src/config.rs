use std::env;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

use crate::error::{AppError, Result};

const DEFAULT_TARGET: &str = "/etc/nix/nix.custom.conf";
const DEFAULT_NIX_CONF: &str = "/etc/nix/nix.conf";
const DEFAULT_SUDO: &str = "/usr/bin/sudo";

#[derive(Clone, Debug)]
pub struct Config {
    pub target: PathBuf,
    pub nix_conf: PathBuf,
    pub nix_conf_explicit: bool,
    pub snippet: PathBuf,
    pub sudo: PathBuf,
    pub elevated: bool,
}

impl Config {
    pub fn from_environment() -> Result<Self> {
        let target = nonempty_environment("APPLY_NIX_SETTINGS_CONF")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_TARGET));
        let explicit_nix_conf = nonempty_environment("APPLY_NIX_SETTINGS_NIX_CONF");
        let nix_conf_explicit = explicit_nix_conf.is_some();
        let nix_conf = explicit_nix_conf
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_NIX_CONF));
        let snippet = nonempty_environment("APPLY_NIX_SETTINGS_SNIPPET")
            .map(PathBuf::from)
            .ok_or_else(|| {
                AppError::new("apply-nix-settings: APPLY_NIX_SETTINGS_SNIPPET is required")
            })?;
        let sudo = nonempty_environment("APPLY_NIX_SETTINGS_SUDO")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(DEFAULT_SUDO));
        let elevated = env::var_os("APPLY_NIX_SETTINGS_ELEVATED").is_some_and(|value| value == "1");
        Ok(Self {
            target,
            nix_conf,
            nix_conf_explicit,
            snippet,
            sudo,
            elevated,
        })
    }

    pub fn include_required(&self) -> bool {
        self.target == Path::new(DEFAULT_TARGET) || self.nix_conf_explicit
    }

    pub fn sudo_assignments(&self) -> Vec<OsString> {
        vec![
            assignment("APPLY_NIX_SETTINGS_ELEVATED", "1"),
            assignment("APPLY_NIX_SETTINGS_CONF", self.target.as_os_str()),
            assignment("APPLY_NIX_SETTINGS_NIX_CONF", self.nix_conf.as_os_str()),
            assignment("APPLY_NIX_SETTINGS_SNIPPET", self.snippet.as_os_str()),
            assignment("APPLY_NIX_SETTINGS_SUDO", self.sudo.as_os_str()),
        ]
    }
}

fn nonempty_environment(name: &str) -> Option<OsString> {
    env::var_os(name).filter(|value| !value.is_empty())
}

fn assignment(name: &str, value: impl AsRef<std::ffi::OsStr>) -> OsString {
    let mut assignment = OsString::from(name);
    assignment.push("=");
    assignment.push(value);
    assignment
}
