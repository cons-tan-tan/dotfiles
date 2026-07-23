use std::process::ExitCode;

use update_pins::cli::{ParseAction, parse_compatible_from, usage};
use update_pins::engine;

fn main() -> ExitCode {
    let action = match parse_compatible_from(std::env::args_os()) {
        Ok(action) => action,
        Err(error) => {
            eprintln!("{error}");
            eprint!("{}", usage());
            return ExitCode::from(2);
        }
    };
    match action {
        ParseAction::Help => {
            print!("{}", usage());
            ExitCode::SUCCESS
        }
        ParseAction::Run(invocation) => match engine::run(invocation) {
            Ok(()) => ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("{error}");
                ExitCode::FAILURE
            }
        },
    }
}
