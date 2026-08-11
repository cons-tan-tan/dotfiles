use std::env;
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::process;

fn main() {
    if let Some(marker) = env::var_os("APPLY_NIX_SETTINGS_FIXTURE_MARKER") {
        fs::write(marker, b"invoked").expect("write invocation marker");
    }
    if let Some(path) = env::var_os("APPLY_NIX_SETTINGS_FIXTURE_ARGS") {
        let mut output = fs::File::create(path).expect("create argument log");
        for argument in env::args_os().skip(1) {
            output
                .write_all(argument.as_os_str().as_bytes())
                .and_then(|()| output.write_all(b"\0"))
                .expect("write argument log");
        }
    }
    if let Some(value) = env::var_os("APPLY_NIX_SETTINGS_FIXTURE_STDOUT") {
        io::stdout()
            .write_all(value.as_os_str().as_bytes())
            .expect("write stdout");
    }
    if let Some(value) = env::var_os("APPLY_NIX_SETTINGS_FIXTURE_STDERR") {
        io::stderr()
            .write_all(value.as_os_str().as_bytes())
            .expect("write stderr");
    }
    let status = env::var("APPLY_NIX_SETTINGS_FIXTURE_EXIT")
        .ok()
        .and_then(|value| value.parse::<i32>().ok())
        .unwrap_or(0);
    process::exit(status);
}
