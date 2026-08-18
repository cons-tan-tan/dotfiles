use std::process::ExitCode;

#[cfg(windows)]
use std::io::{self, IsTerminal, Read, Write};
#[cfg(windows)]
use zeroize::{Zeroize, Zeroizing};

#[cfg(windows)]
mod windows;

fn usage() -> &'static str {
    "Usage: wsl-dpapi.exe <protect|unprotect>\n\n\
     Reads binary data from stdin and writes binary data to stdout.\n\
     Protection uses Windows CurrentUser DPAPI without interactive UI.\n"
}

#[cfg(windows)]
fn read_stdin(limit: usize) -> io::Result<Zeroizing<Vec<u8>>> {
    let mut input = Zeroizing::new(Vec::new());
    io::stdin()
        .lock()
        .take((limit + 1) as u64)
        .read_to_end(&mut input)?;
    if input.len() > limit {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("input exceeds the {limit}-byte limit"),
        ));
    }
    Ok(input)
}

#[cfg(windows)]
fn run(operation: &str) -> Result<(), Box<dyn std::error::Error>> {
    if io::stdin().is_terminal() || io::stdout().is_terminal() {
        return Err("refusing to process protected data through a terminal".into());
    }

    let input_limit = match operation {
        "protect" => wsl_dpapi::MAX_PLAINTEXT_BYTES,
        "unprotect" => wsl_dpapi::MAX_PROTECTED_BYTES,
        _ => unreachable!("operation is validated by main"),
    };
    let mut input = read_stdin(input_limit)?;
    let output = match operation {
        "protect" => {
            let mut envelope = Zeroizing::new(wsl_dpapi::wrap(&input)?);
            windows::protect(&mut envelope)?
        }
        "unprotect" => {
            let mut envelope = windows::unprotect(&mut input)?;
            let result = wsl_dpapi::unwrap(std::mem::take(&mut envelope));
            envelope.zeroize();
            result?
        }
        _ => unreachable!("operation is validated by main"),
    };

    let output = Zeroizing::new(output);
    io::stdout().lock().write_all(&output)?;
    Ok(())
}

#[cfg(not(windows))]
fn run(_operation: &str) -> Result<(), Box<dyn std::error::Error>> {
    Err("wsl-dpapi can only access DPAPI when built for Windows".into())
}

fn main() -> ExitCode {
    let mut arguments = std::env::args();
    let _program = arguments.next();
    let Some(operation) = arguments.next() else {
        eprint!("{}", usage());
        return ExitCode::from(2);
    };
    if operation == "--help" || operation == "-h" {
        print!("{}", usage());
        return ExitCode::SUCCESS;
    }
    if arguments.next().is_some() || !matches!(operation.as_str(), "protect" | "unprotect") {
        eprint!("{}", usage());
        return ExitCode::from(2);
    }

    match run(&operation) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("wsl-dpapi: {error}");
            ExitCode::FAILURE
        }
    }
}
