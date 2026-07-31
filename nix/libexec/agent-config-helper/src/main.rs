use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::path::Path;
use std::process::ExitCode;

use agent_config_helper::app_server;
use agent_config_helper::cli::{self, Action, Command};
use agent_config_helper::error::{AppError, Result};
use agent_config_helper::{hook_state, merge, transforms};
use serde_json::Value;

fn main() -> ExitCode {
    match run_main() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run_main() -> Result<u8> {
    let arguments: Vec<OsString> = env::args_os().skip(1).collect();
    let action = match cli::parse(&arguments) {
        Ok(action) => action,
        Err(error) => {
            eprintln!("{error}");
            eprint!("{}", cli::USAGE);
            return Ok(2);
        }
    };
    match action {
        Action::Help => {
            print!("{}", cli::USAGE);
            Ok(0)
        }
        Action::Run(Command::Merge {
            source,
            payload,
            output,
        }) => {
            merge::merge(&source, &payload, &output)?;
            Ok(0)
        }
        Action::Run(Command::GenerateManagedHookState {
            codex_bin,
            manifest,
            hooks_json_path,
            cwd,
        }) => {
            let manifest = read_json(&manifest, "managed hook manifest")?;
            let specs: Vec<hook_state::HookSpec> =
                serde_json::from_value(manifest).map_err(|error| {
                    AppError::new(format!(
                        "agent-config-helper: invalid managed hook manifest: {error}"
                    ))
                })?;
            let response = app_server::fetch_hooks_list(&codex_bin, &cwd)?;
            write_json(&hook_state::build_payload_for_specs(
                &response,
                &specs,
                &hooks_json_path,
            )?)?;
            Ok(0)
        }
        Action::Run(Command::ClaudeSelectIntegration { settings }) => {
            let settings = read_json(&settings, "Claude settings")?;
            write_json(&transforms::claude_select_integration(&settings)?)?;
            Ok(0)
        }
        Action::Run(Command::ClaudeRewriteSessionCommand { command, settings }) => {
            let settings = read_json(&settings, "Claude settings")?;
            write_json(&transforms::claude_rewrite_session_command(
                &settings, &command,
            )?)?;
            Ok(0)
        }
        Action::Run(Command::ClaudeMergeSettings { base, hcom, herdr }) => {
            let base = read_json(&base, "Claude base settings")?;
            let hcom = read_json(&hcom, "Claude hcom settings")?;
            let herdr = read_json(&herdr, "Claude Herdr settings")?;
            write_json(&transforms::claude_merge_settings(&base, &hcom, &herdr)?)?;
            Ok(0)
        }
        Action::Run(Command::CodexExtractHookState { config }) => {
            let config = fs::read_to_string(&config)
                .map_err(|error| AppError::io("read Codex config TOML", &config, error))?;
            write_json(&transforms::codex_extract_hook_state_from_toml(&config)?)?;
            Ok(0)
        }
        Action::Run(Command::CodexRekeyHookState { hooks_path, state }) => {
            let state = read_json(&state, "Codex hook state")?;
            let hooks_path = hooks_path.to_str().ok_or_else(|| {
                AppError::new(format!(
                    "agent-config-helper: hooks path is not valid UTF-8: {}",
                    hooks_path.display()
                ))
            })?;
            write_json(&transforms::codex_rekey_hook_state(&state, hooks_path)?)?;
            Ok(0)
        }
        Action::Run(Command::CodexApplyHookManifest { manifest, hooks }) => {
            let manifest = read_json(&manifest, "managed hook manifest")?;
            let specs: Vec<hook_state::HookSpec> =
                serde_json::from_value(manifest).map_err(|error| {
                    AppError::new(format!(
                        "agent-config-helper: invalid managed hook manifest: {error}"
                    ))
                })?;
            let hooks = read_json(&hooks, "Codex hooks")?;
            write_json(&transforms::codex_apply_hook_manifest(&hooks, &specs)?)?;
            Ok(0)
        }
        Action::Run(Command::CodexAppendCommandHook {
            event,
            matcher,
            command,
            timeout,
            hooks,
        }) => {
            let hooks = read_json(&hooks, "Codex hooks")?;
            write_json(&transforms::codex_append_command_hook(
                &hooks,
                &event,
                matcher.as_deref(),
                &command,
                timeout,
            )?)?;
            Ok(0)
        }
        Action::Run(Command::CodexMergePayloads { base, hcom, herdr }) => {
            let base = read_json(&base, "Codex base payload")?;
            let hcom = read_json(&hcom, "Codex hcom payload")?;
            let herdr = read_json(&herdr, "Codex Herdr payload")?;
            write_json(&transforms::codex_merge_payloads(&base, &hcom, &herdr)?)?;
            Ok(0)
        }
    }
}

fn read_json(path: &Path, description: &str) -> Result<Value> {
    let bytes = fs::read(path)
        .map_err(|error| AppError::io(&format!("read {description} JSON"), path, error))?;
    serde_json::from_slice(&bytes).map_err(|error| {
        AppError::new(format!(
            "agent-config-helper: invalid {description} JSON in {}: {error}",
            path.display()
        ))
    })
}

fn write_json(value: &Value) -> Result<()> {
    let stdout = io::stdout();
    let mut output = stdout.lock();
    serde_json::to_writer(&mut output, value).map_err(|error| {
        AppError::new(format!(
            "agent-config-helper: cannot write transformed JSON: {error}"
        ))
    })?;
    output.write_all(b"\n").map_err(|error| {
        AppError::new(format!(
            "agent-config-helper: cannot finish transformed JSON: {error}"
        ))
    })?;
    output.flush().map_err(|error| {
        AppError::new(format!(
            "agent-config-helper: cannot flush transformed JSON: {error}"
        ))
    })
}
