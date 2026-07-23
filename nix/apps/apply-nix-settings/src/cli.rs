use std::ffi::{OsStr, OsString};

use crate::error::{AppError, Result};

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Options {
    pub check: bool,
    pub dry_run: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Action {
    Run(Options),
    Help,
}

pub fn parse(arguments: &[OsString]) -> Result<Action> {
    let mut options = Options::default();
    for argument in arguments {
        if argument == OsStr::new("--check") {
            options.check = true;
        } else if argument == OsStr::new("--dry-run") {
            options.dry_run = true;
        } else if argument == OsStr::new("-h") || argument == OsStr::new("--help") {
            return Ok(Action::Help);
        } else {
            return Err(AppError::new(format!(
                "apply-nix-settings: unknown argument: {}",
                argument.to_string_lossy()
            )));
        }
    }
    Ok(Action::Run(options))
}

pub const USAGE: &str = "\
Usage: apply-nix-settings [--check] [--dry-run]

Syncs the managed block in /etc/nix/nix.custom.conf. Set
APPLY_NIX_SETTINGS_CONF to test or target another file. Set
APPLY_NIX_SETTINGS_NIX_CONF to test the nix.conf include check.
";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_supported_flags_and_preserves_check_precedence_state() {
        assert_eq!(
            parse(&[OsString::from("--dry-run"), OsString::from("--check")]).unwrap(),
            Action::Run(Options {
                check: true,
                dry_run: true
            })
        );
    }

    #[test]
    fn help_short_circuits_later_arguments_like_the_shell_cli() {
        assert_eq!(
            parse(&[OsString::from("--help"), OsString::from("--unknown")]).unwrap(),
            Action::Help
        );
    }

    #[test]
    fn rejects_unknown_arguments() {
        assert!(parse(&[OsString::from("--unknown")]).is_err());
    }
}
