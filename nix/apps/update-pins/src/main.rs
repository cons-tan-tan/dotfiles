use std::process::ExitCode;

use clap::Parser;
use update_pins::cli::Cli;

fn main() -> ExitCode {
    let cli = Cli::parse();
    eprintln!(
        "update-pins: Rust updater for {:?} is not implemented yet",
        cli.target
    );
    ExitCode::FAILURE
}
