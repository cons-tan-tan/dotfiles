use std::env;
use std::ffi::OsString;
use std::io::{self, Write};
use std::process::ExitCode;

use codex_config_helper::app_server;
use codex_config_helper::cli::{self, Action, Command};
use codex_config_helper::error::{AppError, Result};
use codex_config_helper::{hook_state, merge};

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
        Action::Run(Command::GenerateHerdrHookState {
            codex_bin,
            hook_command,
            hooks_json_path,
            cwd,
        }) => {
            let response = app_server::fetch_hooks_list(&codex_bin, &cwd)?;
            let payload = hook_state::build_payload(&response, &hook_command, &hooks_json_path)?;
            let stdout = io::stdout();
            let mut output = stdout.lock();
            serde_json::to_writer(&mut output, &payload).map_err(|error| {
                AppError::new(format!(
                    "codex-config-helper: cannot write hook state JSON: {error}"
                ))
            })?;
            output.write_all(b"\n").map_err(|error| {
                AppError::new(format!(
                    "codex-config-helper: cannot finish hook state JSON: {error}"
                ))
            })?;
            output.flush().map_err(|error| {
                AppError::new(format!(
                    "codex-config-helper: cannot flush hook state JSON: {error}"
                ))
            })?;
            Ok(0)
        }
    }
}
