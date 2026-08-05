use std::env;
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::process;

fn main() {
    if let Some(marker) = env::var_os("SAFE_FETCH_FIXTURE_MARKER") {
        fs::write(marker, b"invoked").expect("write invocation marker");
    }

    if env::var_os("SAFE_FETCH_FIXTURE_PRINT_ARGS").is_some() {
        let stdout = io::stdout();
        let mut stdout = stdout.lock();
        for argument in env::args_os().skip(1) {
            writeln!(
                stdout,
                "arg={}",
                encode_hex(argument.as_os_str().as_bytes())
            )
            .expect("write argument");
        }
    }
    if let Some(value) = env::var_os("SAFE_FETCH_FIXTURE_STDOUT") {
        io::stdout()
            .write_all(value.as_os_str().as_bytes())
            .expect("write stdout");
    }
    if let Some(value) = env::var_os("SAFE_FETCH_FIXTURE_STDERR") {
        io::stderr()
            .write_all(value.as_os_str().as_bytes())
            .expect("write stderr");
    }

    let status = env::var("SAFE_FETCH_FIXTURE_EXIT")
        .ok()
        .and_then(|value| value.parse::<i32>().ok())
        .unwrap_or(0);
    process::exit(status);
}

fn encode_hex(value: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(value.len() * 2);
    for byte in value {
        encoded.push(char::from(HEX[usize::from(byte >> 4)]));
        encoded.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    encoded
}
