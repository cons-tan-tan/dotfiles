use std::ffi::{OsStr, OsString};
use std::path::PathBuf;

use crate::error::{AppError, Result};

pub const USAGE: &str = "\
Usage:
  aws-config-helper login --aws-bin PATH --baseline PATH --target PATH -- [AWS_LOGIN_ARGS...]
  aws-config-helper reconcile --baseline PATH --target PATH --managed-section SECTION...
";

#[derive(Debug, Eq, PartialEq)]
pub enum Command {
    Help,
    Login {
        aws_bin: PathBuf,
        baseline: PathBuf,
        target: PathBuf,
        aws_args: Vec<OsString>,
    },
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
        Some("login") => parse_login(&arguments[1..]),
        Some("reconcile") => parse_reconcile(&arguments[1..]),
        _ => Err(usage_error("unknown subcommand")),
    }
}

fn parse_login(arguments: &[OsString]) -> Result<Command> {
    let separator = arguments
        .iter()
        .position(|argument| argument == OsStr::new("--"))
        .ok_or_else(|| usage_error("login requires -- before AWS arguments"))?;
    let options = &arguments[..separator];
    let aws_args = arguments[separator + 1..].to_vec();
    let mut aws_bin = None;
    let mut baseline = None;
    let mut target = None;
    let mut index = 0;
    while index < options.len() {
        let option = options[index]
            .to_str()
            .ok_or_else(|| usage_error("option names must be UTF-8"))?;
        let value = options
            .get(index + 1)
            .ok_or_else(|| usage_error(&format!("{option} requires a value")))?;
        match option {
            "--aws-bin" => set_once_path(&mut aws_bin, value, option)?,
            "--baseline" => set_once_path(&mut baseline, value, option)?,
            "--target" => set_once_path(&mut target, value, option)?,
            _ => return Err(usage_error(&format!("unknown login option {option}"))),
        }
        index += 2;
    }
    Ok(Command::Login {
        aws_bin: required_path(aws_bin, "--aws-bin")?,
        baseline: required_path(baseline, "--baseline")?,
        target: required_path(target, "--target")?,
        aws_args,
    })
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
    fn parses_login_and_preserves_aws_arguments() {
        assert_eq!(
            parse(args(&[
                "login",
                "--target",
                "/target",
                "--aws-bin",
                "/aws",
                "--baseline",
                "/base",
                "--",
                "--profile",
                "test",
            ]))
            .unwrap(),
            Command::Login {
                aws_bin: "/aws".into(),
                baseline: "/base".into(),
                target: "/target".into(),
                aws_args: args(&["--profile", "test"]),
            }
        );
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
        for arguments in [
            args(&["login", "--aws-bin", "/aws", "--"]),
            args(&[
                "login",
                "--aws-bin",
                "/aws",
                "--aws-bin",
                "/other",
                "--baseline",
                "/base",
                "--target",
                "/target",
                "--",
            ]),
            args(&[
                "reconcile",
                "--baseline",
                "/base",
                "--target",
                "/target",
                "--unknown",
                "value",
            ]),
        ] {
            assert!(parse(arguments).is_err());
        }
    }
}
