use std::env;
use std::ffi::OsString;
use std::io::{self, Write};
use std::process::ExitCode;

use apply_nix_settings::app::{self, SystemRuntime};
use apply_nix_settings::config::Config;

fn main() -> ExitCode {
    let config = match Config::from_environment() {
        Ok(config) => config,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };
    let arguments: Vec<OsString> = env::args_os().skip(1).collect();
    let stdout = io::stdout();
    let stderr = io::stderr();
    let mut stdout = stdout.lock();
    let mut stderr = stderr.lock();
    let mut runtime = SystemRuntime;

    match app::run(&config, &arguments, &mut stdout, &mut stderr, &mut runtime) {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            let _ = writeln!(stderr, "{error}");
            ExitCode::FAILURE
        }
    }
}
