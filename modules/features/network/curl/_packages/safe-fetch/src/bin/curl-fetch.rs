use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    let child = match env::var_os("SAFE_FETCH_CURL_BIN").filter(|value| !value.is_empty()) {
        Some(value) => PathBuf::from(value),
        None => {
            eprintln!("curl-fetch: SAFE_FETCH_CURL_BIN is not configured");
            return ExitCode::FAILURE;
        }
    };
    let arguments = match safe_fetch::curl_policy::build_arguments(env::args_os().skip(1).collect())
    {
        Ok(arguments) => arguments,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::FAILURE;
        }
    };
    let error = safe_fetch::process::exec(&child, &arguments);
    eprintln!("curl-fetch: failed to execute {}: {error}", child.display());
    ExitCode::FAILURE
}
