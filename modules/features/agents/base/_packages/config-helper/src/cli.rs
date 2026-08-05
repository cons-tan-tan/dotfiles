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
    GenerateManagedHookState {
        codex_bin: PathBuf,
        manifest: PathBuf,
        hooks_json_path: PathBuf,
        cwd: PathBuf,
    },
    ClaudeSelectIntegration {
        settings: PathBuf,
    },
    ClaudeRewriteSessionCommand {
        command: String,
        settings: PathBuf,
    },
    ClaudeMergeSettings {
        base: PathBuf,
        hcom: PathBuf,
        herdr: PathBuf,
    },
    CodexExtractHookState {
        config: PathBuf,
    },
    CodexRekeyHookState {
        hooks_path: PathBuf,
        state: PathBuf,
    },
    CodexApplyHookManifest {
        manifest: PathBuf,
        hooks: PathBuf,
    },
    CodexAppendCommandHook {
        event: String,
        matcher: Option<String>,
        command: String,
        timeout: u64,
        hooks: PathBuf,
    },
    CodexMergePayloads {
        base: PathBuf,
        hcom: PathBuf,
        herdr: PathBuf,
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
  agent-config-helper generate-managed-hook-state \\
    --codex-bin <path> --manifest <json> --hooks-json-path <path> [--cwd <path>]
  agent-config-helper claude select-integration <settings.json>
  agent-config-helper claude rewrite-session-command --command <command> <settings.json>
  agent-config-helper claude merge-settings --base <json> --hcom <json> --herdr <json>
  agent-config-helper codex extract-hook-state <config.toml>
  agent-config-helper codex rekey-hook-state --hooks-path <path> <state.json>
  agent-config-helper codex apply-hook-manifest --manifest <json> <hooks.json>
  agent-config-helper codex append-command-hook \
    --event <event> [--matcher <regex>] --command <command> --timeout <seconds> <hooks.json>
  agent-config-helper codex merge-payloads <base.json> <hcom.json> <herdr.json>
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
        Some("generate-managed-hook-state") => parse_generate_hook_state(&arguments[1..]),
        Some("claude") => parse_claude(&arguments[1..]),
        Some("codex") => parse_codex(&arguments[1..]),
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

fn parse_generate_hook_state(arguments: &[OsString]) -> Result<Action> {
    if arguments.iter().any(|argument| is_help(argument)) {
        return Ok(Action::Help);
    }
    let mut codex_bin = None;
    let mut manifest = None;
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
            Some("--manifest") => set_once(&mut manifest, PathBuf::from(value), option)?,
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
    Ok(Action::Run(Command::GenerateManagedHookState {
        codex_bin: required(codex_bin, "--codex-bin")?,
        manifest: required(manifest, "--manifest")?,
        hooks_json_path: required(hooks_json_path, "--hooks-json-path")?,
        cwd: cwd.unwrap_or(std::env::current_dir().map_err(|error| {
            AppError::new(format!(
                "agent-config-helper: cannot resolve current directory: {error}"
            ))
        })?),
    }))
}

fn parse_claude(arguments: &[OsString]) -> Result<Action> {
    let Some(subcommand) = arguments.first() else {
        return Err(AppError::new(
            "agent-config-helper: a Claude subcommand is required",
        ));
    };
    if is_help(subcommand) {
        return Ok(Action::Help);
    }
    match subcommand.to_str() {
        Some("select-integration") => parse_claude_select_integration(&arguments[1..]),
        Some("rewrite-session-command") => parse_claude_rewrite_session_command(&arguments[1..]),
        Some("merge-settings") => parse_claude_merge_settings(&arguments[1..]),
        _ => Err(AppError::new(format!(
            "agent-config-helper: unknown Claude subcommand: {}",
            subcommand.to_string_lossy()
        ))),
    }
}

fn parse_claude_select_integration(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &[]) {
        return Ok(Action::Help);
    }
    let settings = exactly_one_path(
        arguments,
        "claude select-integration requires a settings JSON path",
    )?;
    Ok(Action::Run(Command::ClaudeSelectIntegration { settings }))
}

fn parse_claude_rewrite_session_command(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &["--command"]) {
        return Ok(Action::Help);
    }
    let (command, settings) = parse_command_and_path(
        arguments,
        "Claude settings JSON",
        "claude rewrite-session-command",
    )?;
    Ok(Action::Run(Command::ClaudeRewriteSessionCommand {
        command,
        settings,
    }))
}

fn parse_claude_merge_settings(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &["--base", "--hcom", "--herdr"]) {
        return Ok(Action::Help);
    }
    let (base, hcom, herdr) = parse_three_named_paths(arguments, "claude merge-settings")?;
    Ok(Action::Run(Command::ClaudeMergeSettings {
        base,
        hcom,
        herdr,
    }))
}

fn parse_codex(arguments: &[OsString]) -> Result<Action> {
    let Some(subcommand) = arguments.first() else {
        return Err(AppError::new(
            "agent-config-helper: a Codex subcommand is required",
        ));
    };
    if is_help(subcommand) {
        return Ok(Action::Help);
    }
    match subcommand.to_str() {
        Some("extract-hook-state") => parse_codex_extract_hook_state(&arguments[1..]),
        Some("rekey-hook-state") => parse_codex_rekey_hook_state(&arguments[1..]),
        Some("apply-hook-manifest") => parse_codex_apply_hook_manifest(&arguments[1..]),
        Some("append-command-hook") => parse_codex_append_command_hook(&arguments[1..]),
        Some("merge-payloads") => parse_codex_merge_payloads(&arguments[1..]),
        _ => Err(AppError::new(format!(
            "agent-config-helper: unknown Codex subcommand: {}",
            subcommand.to_string_lossy()
        ))),
    }
}

fn parse_codex_extract_hook_state(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &[]) {
        return Ok(Action::Help);
    }
    let config = exactly_one_path(
        arguments,
        "codex extract-hook-state requires a config TOML path",
    )?;
    Ok(Action::Run(Command::CodexExtractHookState { config }))
}

fn parse_codex_rekey_hook_state(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &["--hooks-path"]) {
        return Ok(Action::Help);
    }
    let mut hooks_path = None;
    let mut state = None;
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        match argument.to_str() {
            Some("--hooks-path") => {
                let value = option_value(arguments, index, argument)?;
                set_once(&mut hooks_path, PathBuf::from(value), argument)?;
                index += 2;
            }
            Some(value) if value.starts_with('-') => return Err(unknown_option(argument)),
            _ => {
                set_positional_once(
                    &mut state,
                    PathBuf::from(argument),
                    argument,
                    "codex rekey-hook-state",
                )?;
                index += 1;
            }
        }
    }
    Ok(Action::Run(Command::CodexRekeyHookState {
        hooks_path: required(hooks_path, "--hooks-path")?,
        state: required_path(state, "codex rekey-hook-state requires a state JSON path")?,
    }))
}

fn parse_codex_apply_hook_manifest(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &["--manifest"]) {
        return Ok(Action::Help);
    }
    let mut manifest = None;
    let mut hooks = None;
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        match argument.to_str() {
            Some("--manifest") => {
                let value = option_value(arguments, index, argument)?;
                set_once(&mut manifest, PathBuf::from(value), argument)?;
                index += 2;
            }
            Some(value) if value.starts_with('-') => return Err(unknown_option(argument)),
            _ => {
                set_positional_once(
                    &mut hooks,
                    PathBuf::from(argument),
                    argument,
                    "codex apply-hook-manifest",
                )?;
                index += 1;
            }
        }
    }
    Ok(Action::Run(Command::CodexApplyHookManifest {
        manifest: required(manifest, "--manifest")?,
        hooks: required_path(
            hooks,
            "codex apply-hook-manifest requires a hooks JSON path",
        )?,
    }))
}

fn parse_codex_append_command_hook(arguments: &[OsString]) -> Result<Action> {
    if help_requested(
        arguments,
        &["--event", "--matcher", "--command", "--timeout"],
    ) {
        return Ok(Action::Help);
    }
    let mut event = None;
    let mut matcher = None;
    let mut command = None;
    let mut timeout = None;
    let mut hooks = None;
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        match argument.to_str() {
            Some("--event" | "--matcher" | "--command" | "--timeout") => {
                let value = option_value(arguments, index, argument)?;
                let text = value.to_str().ok_or_else(|| {
                    AppError::new("agent-config-helper: hook metadata must be valid UTF-8")
                })?;
                match argument.to_str() {
                    Some("--event") => set_once(&mut event, text.to_owned(), argument)?,
                    Some("--matcher") => set_once(&mut matcher, text.to_owned(), argument)?,
                    Some("--command") => set_once(&mut command, text.to_owned(), argument)?,
                    Some("--timeout") => {
                        let seconds = text.parse::<u64>().map_err(|_| {
                            AppError::new("agent-config-helper: --timeout must be an integer")
                        })?;
                        set_once(&mut timeout, seconds, argument)?;
                    }
                    _ => unreachable!(),
                }
                index += 2;
            }
            Some(value) if value.starts_with('-') => return Err(unknown_option(argument)),
            _ => {
                set_positional_once(
                    &mut hooks,
                    PathBuf::from(argument),
                    argument,
                    "codex append-command-hook",
                )?;
                index += 1;
            }
        }
    }
    Ok(Action::Run(Command::CodexAppendCommandHook {
        event: required(event, "--event")?,
        matcher,
        command: required(command, "--command")?,
        timeout: required(timeout, "--timeout")?,
        hooks: required_path(
            hooks,
            "codex append-command-hook requires a hooks JSON path",
        )?,
    }))
}

fn parse_codex_merge_payloads(arguments: &[OsString]) -> Result<Action> {
    if help_requested(arguments, &[]) {
        return Ok(Action::Help);
    }
    let [base, hcom, herdr] = arguments else {
        return Err(AppError::new(
            "agent-config-helper: codex merge-payloads requires base, hcom, and Herdr JSON paths",
        ));
    };
    Ok(Action::Run(Command::CodexMergePayloads {
        base: base.into(),
        hcom: hcom.into(),
        herdr: herdr.into(),
    }))
}

fn exactly_one_path(arguments: &[OsString], message: &str) -> Result<PathBuf> {
    let [path] = arguments else {
        return Err(AppError::new(format!("agent-config-helper: {message}")));
    };
    Ok(path.into())
}

fn parse_command_and_path(
    arguments: &[OsString],
    path_name: &str,
    command_name: &str,
) -> Result<(String, PathBuf)> {
    let mut command = None;
    let mut path = None;
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        match argument.to_str() {
            Some("--command") => {
                let value = option_value(arguments, index, argument)?;
                let value = value.to_str().ok_or_else(|| {
                    AppError::new("agent-config-helper: command must be valid UTF-8")
                })?;
                set_once(&mut command, value.to_owned(), argument)?;
                index += 2;
            }
            Some(value) if value.starts_with('-') => return Err(unknown_option(argument)),
            _ => {
                set_positional_once(&mut path, PathBuf::from(argument), argument, command_name)?;
                index += 1;
            }
        }
    }

    Ok((
        required(command, "--command")?,
        required_path(path, &format!("{command_name} requires a {path_name} path"))?,
    ))
}

fn parse_three_named_paths(
    arguments: &[OsString],
    command_name: &str,
) -> Result<(PathBuf, PathBuf, PathBuf)> {
    let mut base = None;
    let mut hcom = None;
    let mut herdr = None;
    let mut index = 0;
    while index < arguments.len() {
        let option = &arguments[index];
        match option.to_str() {
            Some("--base") => {
                let value = option_value(arguments, index, option)?;
                set_once(&mut base, PathBuf::from(value), option)?;
            }
            Some("--hcom") => {
                let value = option_value(arguments, index, option)?;
                set_once(&mut hcom, PathBuf::from(value), option)?;
            }
            Some("--herdr") => {
                let value = option_value(arguments, index, option)?;
                set_once(&mut herdr, PathBuf::from(value), option)?;
            }
            _ => return Err(unknown_option(option)),
        }
        index += 2;
    }
    Ok((
        required(base, &format!("{command_name}: --base"))?,
        required(hcom, &format!("{command_name}: --hcom"))?,
        required(herdr, &format!("{command_name}: --herdr"))?,
    ))
}

fn option_value<'a>(
    arguments: &'a [OsString],
    index: usize,
    option: &OsStr,
) -> Result<&'a OsString> {
    arguments.get(index + 1).ok_or_else(|| {
        AppError::new(format!(
            "agent-config-helper: {} requires a value",
            option.to_string_lossy()
        ))
    })
}

fn set_positional_once<T>(
    slot: &mut Option<T>,
    value: T,
    argument: &OsStr,
    command_name: &str,
) -> Result<()> {
    if slot.replace(value).is_some() {
        return Err(AppError::new(format!(
            "agent-config-helper: {command_name} received an unexpected argument: {}",
            argument.to_string_lossy()
        )));
    }
    Ok(())
}

fn required_path(value: Option<PathBuf>, message: &str) -> Result<PathBuf> {
    value.ok_or_else(|| AppError::new(format!("agent-config-helper: {message}")))
}

fn unknown_option(option: &OsStr) -> AppError {
    AppError::new(format!(
        "agent-config-helper: unknown option: {}",
        option.to_string_lossy()
    ))
}

fn is_help(argument: &OsStr) -> bool {
    argument == OsStr::new("-h") || argument == OsStr::new("--help")
}

fn help_requested(arguments: &[OsString], value_options: &[&str]) -> bool {
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        if is_help(argument) {
            return true;
        }
        if argument
            .to_str()
            .is_some_and(|argument| value_options.contains(&argument))
        {
            index += 2;
        } else {
            index += 1;
        }
    }
    false
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
                "generate-managed-hook-state",
                "--manifest",
                "manifest.json",
                "--hooks-json-path",
                "/home/me/.codex/hooks.json",
                "--codex-bin",
                "/nix/store/codex",
                "--cwd",
                "/repo",
            ]))
            .unwrap(),
            Action::Run(Command::GenerateManagedHookState {
                codex_bin: "/nix/store/codex".into(),
                manifest: "manifest.json".into(),
                hooks_json_path: "/home/me/.codex/hooks.json".into(),
                cwd: "/repo".into(),
            })
        );
    }

    #[test]
    fn rejects_missing_duplicate_and_unknown_options() {
        assert!(parse(&args(&["generate-managed-hook-state"])).is_err());
        assert!(
            parse(&args(&[
                "generate-managed-hook-state",
                "--codex-bin",
                "/one",
                "--codex-bin",
                "/two",
            ]))
            .is_err()
        );
        assert!(
            parse(&args(&[
                "generate-managed-hook-state",
                "--unknown",
                "value"
            ]))
            .is_err()
        );
    }

    #[test]
    fn parses_all_claude_commands_and_named_options_in_any_order() {
        assert_eq!(
            parse(&args(&["claude", "select-integration", "settings.json"])).unwrap(),
            Action::Run(Command::ClaudeSelectIntegration {
                settings: "settings.json".into(),
            })
        );
        assert_eq!(
            parse(&args(&[
                "claude",
                "rewrite-session-command",
                "settings.json",
                "--command",
                "hcom hook",
            ]))
            .unwrap(),
            Action::Run(Command::ClaudeRewriteSessionCommand {
                command: "hcom hook".to_owned(),
                settings: "settings.json".into(),
            })
        );
        assert_eq!(
            parse(&args(&[
                "claude",
                "merge-settings",
                "--herdr",
                "herdr.json",
                "--base",
                "base.json",
                "--hcom",
                "hcom.json",
            ]))
            .unwrap(),
            Action::Run(Command::ClaudeMergeSettings {
                base: "base.json".into(),
                hcom: "hcom.json".into(),
                herdr: "herdr.json".into(),
            })
        );
    }

    #[test]
    fn parses_all_codex_commands_and_named_options_in_any_order() {
        assert_eq!(
            parse(&args(&["codex", "extract-hook-state", "config.toml"])).unwrap(),
            Action::Run(Command::CodexExtractHookState {
                config: "config.toml".into(),
            })
        );
        assert_eq!(
            parse(&args(&[
                "codex",
                "rekey-hook-state",
                "state.json",
                "--hooks-path",
                "/home/me/.codex/hooks.json",
            ]))
            .unwrap(),
            Action::Run(Command::CodexRekeyHookState {
                hooks_path: "/home/me/.codex/hooks.json".into(),
                state: "state.json".into(),
            })
        );
        assert_eq!(
            parse(&args(&[
                "codex",
                "apply-hook-manifest",
                "hooks.json",
                "--manifest",
                "manifest.json",
            ]))
            .unwrap(),
            Action::Run(Command::CodexApplyHookManifest {
                manifest: "manifest.json".into(),
                hooks: "hooks.json".into(),
            })
        );
        assert_eq!(
            parse(&args(&[
                "codex",
                "append-command-hook",
                "--timeout",
                "10",
                "--command",
                "guard",
                "hooks.json",
                "--event",
                "PreToolUse",
                "--matcher",
                "Bash",
            ]))
            .unwrap(),
            Action::Run(Command::CodexAppendCommandHook {
                event: "PreToolUse".to_owned(),
                matcher: Some("Bash".to_owned()),
                command: "guard".to_owned(),
                timeout: 10,
                hooks: "hooks.json".into(),
            })
        );
        assert_eq!(
            parse(&args(&[
                "codex",
                "merge-payloads",
                "base.json",
                "hcom.json",
                "herdr.json",
            ]))
            .unwrap(),
            Action::Run(Command::CodexMergePayloads {
                base: "base.json".into(),
                hcom: "hcom.json".into(),
                herdr: "herdr.json".into(),
            })
        );
    }

    #[test]
    fn new_commands_reject_missing_duplicate_unknown_and_extra_arguments() {
        for arguments in [
            &["claude", "select-integration"][..],
            &["claude", "rewrite-session-command", "--command", "hook"],
            &[
                "claude",
                "merge-settings",
                "--base",
                "base",
                "--hcom",
                "hcom",
            ],
            &["codex", "extract-hook-state"],
            &["codex", "rekey-hook-state", "state"],
            &["codex", "apply-hook-manifest", "hooks"],
            &["codex", "merge-payloads", "base", "hcom"],
        ] {
            assert!(parse(&args(arguments)).is_err(), "{arguments:?}");
        }

        for arguments in [
            &[
                "claude",
                "rewrite-session-command",
                "--command",
                "one",
                "--command",
                "two",
                "settings",
            ][..],
            &[
                "claude",
                "merge-settings",
                "--base",
                "one",
                "--base",
                "two",
                "--hcom",
                "hcom",
                "--herdr",
                "herdr",
            ],
            &[
                "codex",
                "rekey-hook-state",
                "--hooks-path",
                "one",
                "--hooks-path",
                "two",
                "state",
            ],
        ] {
            assert!(parse(&args(arguments)).is_err(), "{arguments:?}");
        }

        for arguments in [
            &[
                "claude",
                "rewrite-session-command",
                "--unknown",
                "value",
                "settings",
            ][..],
            &[
                "claude",
                "merge-settings",
                "--base",
                "base",
                "--hcom",
                "hcom",
                "--unknown",
                "value",
                "--herdr",
                "herdr",
            ],
            &["codex", "rekey-hook-state", "--unknown", "value", "state"],
            &[
                "codex",
                "apply-hook-manifest",
                "--unknown",
                "value",
                "hooks",
            ],
        ] {
            assert!(parse(&args(arguments)).is_err(), "{arguments:?}");
        }
        assert_eq!(
            parse(&args(&["claude", "merge-settings", "--unknown"]))
                .unwrap_err()
                .to_string(),
            "agent-config-helper: unknown option: --unknown"
        );

        assert!(
            parse(&args(&[
                "codex",
                "apply-hook-manifest",
                "--manifest",
                "manifest",
                "one",
                "two",
            ]))
            .is_err()
        );
    }

    #[cfg(unix)]
    #[test]
    fn command_requires_utf8_but_paths_remain_os_strings() {
        use std::os::unix::ffi::OsStringExt;

        let invalid = OsString::from_vec(vec![0xff]);
        let invalid_command = vec![
            OsString::from("codex"),
            OsString::from("append-command-hook"),
            OsString::from("--command"),
            invalid.clone(),
            OsString::from("--event"),
            OsString::from("SessionStart"),
            OsString::from("--timeout"),
            OsString::from("10"),
            OsString::from("hooks.json"),
        ];
        assert!(parse(&invalid_command).is_err());

        let invalid_path = vec![
            OsString::from("claude"),
            OsString::from("select-integration"),
            invalid.clone(),
        ];
        assert_eq!(
            parse(&invalid_path).unwrap(),
            Action::Run(Command::ClaudeSelectIntegration {
                settings: PathBuf::from(invalid),
            })
        );
    }

    #[test]
    fn help_succeeds_for_the_root_and_subcommands() {
        assert_eq!(parse(&args(&["--help"])).unwrap(), Action::Help);
        assert_eq!(parse(&args(&["merge", "--help"])).unwrap(), Action::Help);
        assert_eq!(parse(&args(&["claude", "--help"])).unwrap(), Action::Help);
        assert_eq!(
            parse(&args(&["codex", "merge-payloads", "--help"])).unwrap(),
            Action::Help
        );
        assert_eq!(
            parse(&args(&[
                "claude",
                "merge-settings",
                "--base",
                "base",
                "--help",
            ]))
            .unwrap(),
            Action::Help
        );
        assert!(parse(&args(&["claude", "bogus", "--help"])).is_err());
    }
}
