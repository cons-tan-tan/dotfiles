use std::io::{self, Read, Write};
use std::process::ExitCode;

const MAGIC: &[u8] = b"TESTDPAPI1";

fn main() -> ExitCode {
    let Some(operation) = std::env::args().nth(1) else {
        return ExitCode::from(2);
    };
    let mut input = Vec::new();
    if io::stdin().read_to_end(&mut input).is_err() {
        return ExitCode::FAILURE;
    }

    let output = match operation.as_str() {
        "protect" => {
            let mut protected = MAGIC.to_vec();
            protected.extend(input);
            protected
        }
        "unprotect" if input.starts_with(MAGIC) => input[MAGIC.len()..].to_vec(),
        "unprotect" => {
            eprintln!("test fixture: corrupt protected input");
            return ExitCode::FAILURE;
        }
        _ => return ExitCode::from(2),
    };

    if io::stdout().write_all(&output).is_err() {
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
