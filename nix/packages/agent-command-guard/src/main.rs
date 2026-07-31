use std::{env, path::PathBuf, process::ExitCode};

use agent_command_guard::{
    Decision, HookInput, Policy, assess,
    protocol::{deny_output, safe_output},
    validate_policy,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Hook,
    Validate,
    List,
}

fn main() -> ExitCode {
    let (mode, policy_path) = match parse_args() {
        Ok(value) => value,
        Err(error) => {
            eprintln!("agent-command-guard: {error}");
            return ExitCode::from(2);
        }
    };

    match mode {
        Mode::Validate | Mode::List => match load(&policy_path) {
            Ok(policy) => {
                if mode == Mode::List {
                    for id in policy.effective_shellfirm_ids() {
                        println!("{id}");
                    }
                }
                ExitCode::SUCCESS
            }
            Err(error) => {
                eprintln!("agent-command-guard: {error}");
                ExitCode::FAILURE
            }
        },
        Mode::Hook => {
            let result = load(&policy_path).and_then(|policy| {
                HookInput::read(std::io::stdin().lock()).map(|input| assess(&input, &policy))
            });
            match result {
                Ok(Decision::Safe) => println!("{}", safe_output()),
                Ok(Decision::Deny { reason }) => println!("{}", deny_output(&reason)),
                Err(error) => println!(
                    "{}",
                    deny_output(&format!(
                        "The shared command policy failed closed: {error}. Retry with a simpler static command."
                    ))
                ),
            }
            ExitCode::SUCCESS
        }
    }
}

fn load(
    path: &std::path::Path,
) -> agent_command_guard::Result<agent_command_guard::ValidatedPolicy> {
    validate_policy(Policy::load(path)?)
}

fn parse_args() -> Result<(Mode, PathBuf), String> {
    let mut mode = Mode::Hook;
    let mut policy = None;
    let mut args = env::args_os().skip(1);
    while let Some(argument) = args.next() {
        match argument.to_str() {
            Some("--policy") => {
                let value = args
                    .next()
                    .ok_or_else(|| "--policy requires a path".to_owned())?;
                if policy.replace(PathBuf::from(value)).is_some() {
                    return Err("--policy may only be specified once".to_owned());
                }
            }
            Some("--validate-policy") if mode == Mode::Hook => mode = Mode::Validate,
            Some("--list-effective-shellfirm-rules") if mode == Mode::Hook => mode = Mode::List,
            Some("--validate-policy" | "--list-effective-shellfirm-rules") => {
                return Err("validation and listing modes are mutually exclusive".to_owned());
            }
            Some(value) => return Err(format!("unknown argument {value}")),
            None => return Err("arguments must be valid UTF-8".to_owned()),
        }
    }
    let policy = policy.ok_or_else(|| "--policy is required".to_owned())?;
    Ok((mode, policy))
}
