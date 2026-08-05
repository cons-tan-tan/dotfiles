use std::process::ExitCode;
use std::time::Instant;

use update_pins::smoke;

fn main() -> ExitCode {
    if std::env::args_os().len() != 1 {
        eprintln!("Usage: update-pins-smoke");
        return ExitCode::from(2);
    }

    let started = Instant::now();
    match smoke::run() {
        Ok(report) => {
            println!("GitHub release shape: {}", report.github_release_version);
            println!("npm latest shape: {}", report.npm_version);
            println!("Codex appcast shape: {}", report.codex_app_version);
            println!(
                "shellfirm source shape: {} ({} bytes, {})",
                report.shellfirm_version, report.shellfirm_download_bytes, report.shellfirm_hash
            );
            println!(
                "update-pins upstream smoke passed in {:.2?}",
                started.elapsed()
            );
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
