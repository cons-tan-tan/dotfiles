use std::io;
use std::process::ExitCode;

use apply_secrets::cli::{Action, USAGE};
use apply_secrets::{Config, args_without_program, execute};

fn main() -> ExitCode {
    let action = match apply_secrets::cli::parse(args_without_program()) {
        Ok(action) => action,
        Err(error) => {
            eprintln!("apply-secrets: {error}");
            eprint!("{USAGE}");
            return ExitCode::from(2);
        }
    };

    let Action::Run { dry_run } = action else {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    };

    let config = match Config::from_env() {
        Ok(config) => config,
        Err(error) => {
            eprintln!("apply-secrets: {error}");
            return ExitCode::FAILURE;
        }
    };

    match execute(
        &config,
        dry_run,
        &mut io::stdout().lock(),
        &mut io::stderr().lock(),
    ) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("apply-secrets: {error}");
            ExitCode::FAILURE
        }
    }
}
