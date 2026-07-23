use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let child = match env::var_os("SAFE_FETCH_GH_BIN").filter(|value| !value.is_empty()) {
        Some(value) => PathBuf::from(value),
        None => {
            eprintln!("gh-api-get: SAFE_FETCH_GH_BIN is not configured");
            return ExitCode::FAILURE;
        }
    };
    let arguments = match safe_fetch::gh_policy::build_arguments(env::args_os().skip(1).collect()) {
        Ok(arguments) => arguments,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::from(2);
        }
    };
    let error = safe_fetch::process::exec(&child, &arguments);
    eprintln!("gh-api-get: failed to execute {}: {error}", child.display());
    ExitCode::FAILURE
}
