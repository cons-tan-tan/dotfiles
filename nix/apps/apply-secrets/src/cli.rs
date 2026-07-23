use std::ffi::OsString;

pub const USAGE: &str = "\
Usage: apply-secrets [--dry-run]

Decrypts the manifest entries into the configured home directory.

Options:
  --dry-run  Validate the manifest and list destinations without writing
  -h, --help Show this help
";

#[derive(Debug, Eq, PartialEq)]
pub enum Action {
    Run { dry_run: bool },
    Help,
}

pub fn parse(args: impl IntoIterator<Item = OsString>) -> Result<Action, String> {
    let mut dry_run = false;
    let mut help = false;
    for argument in args {
        match argument.to_str() {
            Some("--dry-run") if !dry_run => dry_run = true,
            Some("-h" | "--help") => help = true,
            Some(value) => return Err(format!("unknown argument: {value}")),
            None => return Err("arguments must be valid UTF-8".to_owned()),
        }
    }
    if help {
        Ok(Action::Help)
    } else {
        Ok(Action::Run { dry_run })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_dry_run() {
        assert_eq!(
            parse([OsString::from("--dry-run")]),
            Ok(Action::Run { dry_run: true })
        );
    }

    #[test]
    fn rejects_unknown_and_duplicate_arguments() {
        assert!(parse([OsString::from("--unknown")]).is_err());
        assert!(parse([OsString::from("--help"), OsString::from("--unknown")]).is_err());
        assert!(parse([OsString::from("--dry-run"), OsString::from("--dry-run")]).is_err());
    }
}
