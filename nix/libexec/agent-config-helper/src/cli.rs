use std::ffi::{OsStr, OsString};
use std::path::PathBuf;

use crate::error::{AppError, Result};

#[derive(Debug, Eq, PartialEq)]
pub enum Command {
    Merge {
        source: PathBuf,
        payload: PathBuf,
        output: PathBuf,
    },
    GenerateHerdrHookState {
        codex_bin: PathBuf,
        hook_command: String,
        hooks_json_path: PathBuf,
        cwd: PathBuf,
    },
}

#[derive(Debug, Eq, PartialEq)]
pub enum Action {
    Run(Command),
    Help,
}

pub const USAGE: &str = "\
Usage:
  agent-config-helper merge <source.toml> <payload.json> <output.toml>
  agent-config-helper generate-herdr-hook-state \\
    --codex-bin <path> --hook-command <command> --hooks-json-path <path> [--cwd <path>]
";

pub fn parse(arguments: &[OsString]) -> Result<Action> {
    let Some(subcommand) = arguments.first() else {
        return Err(AppError::new(
            "agent-config-helper: a subcommand is required",
        ));
    };
    if is_help(subcommand) {
        return Ok(Action::Help);
    }
    match subcommand.to_str() {
        Some("merge") => parse_merge(&arguments[1..]),
        Some("generate-herdr-hook-state") => parse_generate(&arguments[1..]),
        _ => Err(AppError::new(format!(
            "agent-config-helper: unknown subcommand: {}",
            subcommand.to_string_lossy()
        ))),
    }
}

fn parse_merge(arguments: &[OsString]) -> Result<Action> {
    if arguments.iter().any(|argument| is_help(argument)) {
        return Ok(Action::Help);
    }
    let [source, payload, output] = arguments else {
        return Err(AppError::new(
            "agent-config-helper: merge requires source, payload, and output paths",
        ));
    };
    Ok(Action::Run(Command::Merge {
        source: source.into(),
        payload: payload.into(),
        output: output.into(),
    }))
}

fn parse_generate(arguments: &[OsString]) -> Result<Action> {
    if arguments.iter().any(|argument| is_help(argument)) {
        return Ok(Action::Help);
    }
    let mut codex_bin = None;
    let mut hook_command = None;
    let mut hooks_json_path = None;
    let mut cwd = None;
    let mut index = 0;
    while index < arguments.len() {
        let option = &arguments[index];
        let value = arguments.get(index + 1).ok_or_else(|| {
            AppError::new(format!(
                "agent-config-helper: {} requires a value",
                option.to_string_lossy()
            ))
        })?;
        match option.to_str() {
            Some("--codex-bin") => set_once(&mut codex_bin, PathBuf::from(value), option)?,
            Some("--hook-command") => {
                let value = value.to_str().ok_or_else(|| {
                    AppError::new("agent-config-helper: hook command must be valid UTF-8")
                })?;
                set_once(&mut hook_command, value.to_owned(), option)?;
            }
            Some("--hooks-json-path") => {
                set_once(&mut hooks_json_path, PathBuf::from(value), option)?;
            }
            Some("--cwd") => set_once(&mut cwd, PathBuf::from(value), option)?,
            _ => {
                return Err(AppError::new(format!(
                    "agent-config-helper: unknown option: {}",
                    option.to_string_lossy()
                )));
            }
        }
        index += 2;
    }

    Ok(Action::Run(Command::GenerateHerdrHookState {
        codex_bin: required(codex_bin, "--codex-bin")?,
        hook_command: required(hook_command, "--hook-command")?,
        hooks_json_path: required(hooks_json_path, "--hooks-json-path")?,
        cwd: cwd.unwrap_or(std::env::current_dir().map_err(|error| {
            AppError::new(format!(
                "agent-config-helper: cannot resolve current directory: {error}"
            ))
        })?),
    }))
}

fn is_help(argument: &OsStr) -> bool {
    argument == OsStr::new("-h") || argument == OsStr::new("--help")
}

fn set_once<T>(slot: &mut Option<T>, value: T, option: &OsStr) -> Result<()> {
    if slot.replace(value).is_some() {
        return Err(AppError::new(format!(
            "agent-config-helper: duplicate option: {}",
            option.to_string_lossy()
        )));
    }
    Ok(())
}

fn required<T>(value: Option<T>, option: &str) -> Result<T> {
    value.ok_or_else(|| AppError::new(format!("agent-config-helper: {option} is required")))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(arguments: &[&str]) -> Vec<OsString> {
        arguments.iter().map(OsString::from).collect()
    }

    #[test]
    fn parses_merge_paths() {
        assert_eq!(
            parse(&args(&["merge", "source", "payload", "output"])).unwrap(),
            Action::Run(Command::Merge {
                source: "source".into(),
                payload: "payload".into(),
                output: "output".into(),
            })
        );
    }

    #[test]
    fn parses_generate_options_in_any_order() {
        assert_eq!(
            parse(&args(&[
                "generate-herdr-hook-state",
                "--hook-command",
                "hook command",
                "--cwd",
                "/repo",
                "--hooks-json-path",
                "/home/me/.codex/hooks.json",
                "--codex-bin",
                "/nix/store/codex",
            ]))
            .unwrap(),
            Action::Run(Command::GenerateHerdrHookState {
                codex_bin: "/nix/store/codex".into(),
                hook_command: "hook command".into(),
                hooks_json_path: "/home/me/.codex/hooks.json".into(),
                cwd: "/repo".into(),
            })
        );
    }

    #[test]
    fn rejects_missing_duplicate_and_unknown_options() {
        assert!(parse(&args(&["generate-herdr-hook-state"])).is_err());
        assert!(
            parse(&args(&[
                "generate-herdr-hook-state",
                "--codex-bin",
                "/one",
                "--codex-bin",
                "/two",
            ]))
            .is_err()
        );
        assert!(parse(&args(&["generate-herdr-hook-state", "--unknown", "value"])).is_err());
    }

    #[test]
    fn help_succeeds_for_the_root_and_subcommands() {
        assert_eq!(parse(&args(&["--help"])).unwrap(), Action::Help);
        assert_eq!(parse(&args(&["merge", "--help"])).unwrap(), Action::Help);
    }
}
