mod cli;
mod discovery;
mod language_server;
mod report;

use std::process::ExitCode;

fn main() -> ExitCode {
    match cli::run(std::env::args_os().skip(1)) {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("gha-diag: {}", report::sanitize_log_text(&error));
            ExitCode::from(2)
        }
    }
}
