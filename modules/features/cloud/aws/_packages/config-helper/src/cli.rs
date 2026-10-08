use std::ffi::{OsStr, OsString};
use std::path::PathBuf;

use crate::error::{AppError, Result};

pub const USAGE: &str = "\
Usage:
  aws-config-helper reconcile --baseline PATH --target PATH --managed-section SECTION...
";

#[derive(Debug, Eq, PartialEq)]
pub enum Command {
    Help,
    Reconcile {
        baseline: PathBuf,
        target: PathBuf,
        managed_sections: Vec<String>,
    },
}

pub fn parse(arguments: impl IntoIterator<Item = OsString>) -> Result<Command> {
    let arguments = arguments.into_iter().collect::<Vec<_>>();
    let Some(subcommand) = arguments.first() else {
        return Err(usage_error("missing subcommand"));
    };
    if subcommand == OsStr::new("--help") || subcommand == OsStr::new("-h") {
        return Ok(Command::Help);
    }
    match subcommand.to_str() {
        Some("reconcile") => parse_reconcile(&arguments[1..]),
        _ => Err(usage_error("unknown subcommand")),
    }
}

fn parse_reconcile(arguments: &[OsString]) -> Result<Command> {
    let mut baseline = None;
    let mut target = None;
    let mut managed_sections = Vec::new();
    let mut index = 0;
    while index < arguments.len() {
        let option = arguments[index]
            .to_str()
            .ok_or_else(|| usage_error("option names must be UTF-8"))?;
        let value = arguments
            .get(index + 1)
            .ok_or_else(|| usage_error(&format!("{option} requires a value")))?;
        match option {
            "--baseline" => set_once_path(&mut baseline, value, option)?,
            "--target" => set_once_path(&mut target, value, option)?,
            "--managed-section" => {
                let value = value
                    .to_str()
                    .ok_or_else(|| usage_error("managed section names must be UTF-8"))?;
                managed_sections.push(value.to_string());
            }
            _ => return Err(usage_error(&format!("unknown reconcile option {option}"))),
        }
        index += 2;
    }
    if managed_sections.is_empty() {
        return Err(usage_error(
            "reconcile requires at least one --managed-section",
        ));
    }
    Ok(Command::Reconcile {
        baseline: required_path(baseline, "--baseline")?,
        target: required_path(target, "--target")?,
        managed_sections,
    })
}

fn set_once_path(destination: &mut Option<PathBuf>, value: &OsStr, option: &str) -> Result<()> {
    if destination.replace(PathBuf::from(value)).is_some() {
        return Err(usage_error(&format!("{option} may only be specified once")));
    }
    Ok(())
}

fn required_path(value: Option<PathBuf>, option: &str) -> Result<PathBuf> {
    value.ok_or_else(|| usage_error(&format!("missing required option {option}")))
}

fn usage_error(message: &str) -> AppError {
    AppError::new(format!("aws-config-helper: {message}\n{USAGE}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    #[test]
    fn parses_reconcile_with_repeated_managed_sections() {
        assert_eq!(
            parse(args(&[
                "reconcile",
                "--baseline",
                "/base",
                "--managed-section",
                "default",
                "--target",
                "/target",
                "--managed-section",
                "profile test",
            ]))
            .unwrap(),
            Command::Reconcile {
                baseline: "/base".into(),
                target: "/target".into(),
                managed_sections: vec!["default".to_string(), "profile test".to_string()],
            }
        );
    }

    #[test]
    fn rejects_missing_duplicate_and_unknown_options() {
        for (arguments, expected) in [
            (
                args(&[
                    "reconcile",
                    "--target",
                    "/target",
                    "--managed-section",
                    "default",
                ]),
                "missing required option --baseline",
            ),
            (
                args(&["reconcile", "--baseline", "/base", "--baseline", "/other"]),
                "--baseline may only be specified once",
            ),
            (
                args(&["reconcile", "--unknown", "value"]),
                "unknown reconcile option --unknown",
            ),
            (
                args(&["reconcile", "--baseline", "/base", "--target", "/target"]),
                "reconcile requires at least one --managed-section",
            ),
        ] {
            assert!(parse(arguments).unwrap_err().to_string().contains(expected));
        }
    }
}
