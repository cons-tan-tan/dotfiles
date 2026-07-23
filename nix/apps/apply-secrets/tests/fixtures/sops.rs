use std::env;
use std::ffi::OsStr;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process;

const END_INVOCATION: u32 = u32::MAX;

fn main() {
    let arguments = env::args_os().skip(1).collect::<Vec<_>>();
    if let Some(log) = env::var_os("APPLY_SECRETS_FIXTURE_LOG") {
        append_invocation(Path::new(&log), &arguments);
    }

    let Some(source) = arguments.last() else {
        eprintln!("sops fixture: missing source argument");
        process::exit(64);
    };
    let source_path = Path::new(source);

    if env::var_os("APPLY_SECRETS_FIXTURE_BLOCK_SOURCE").as_deref() == source_path.file_name() {
        let block_path =
            env::var_os("APPLY_SECRETS_FIXTURE_BLOCK_PATH").expect("block path must be configured");
        fs::create_dir_all(block_path).expect("create publish blocker");
    }

    let input = fs::read(source_path).expect("read fixture source");
    if input == b"FAIL\n" {
        eprintln!("sops fixture: synthetic decryption failure");
        process::exit(23);
    }
    if input == b"ABORT\n" {
        process::abort();
    }
    let output = input
        .strip_prefix(b"RAW\n")
        .or_else(|| input.strip_prefix(b"JSON\n"))
        .unwrap_or_else(|| {
            eprintln!("sops fixture: unknown source payload");
            process::exit(65);
        });
    io::stdout()
        .write_all(output)
        .expect("write fixture output");
}

fn append_invocation(path: &Path, arguments: &[impl AsRef<OsStr>]) {
    let mut log = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("open invocation log");
    for argument in arguments {
        let bytes = argument.as_ref().as_bytes();
        let length = u32::try_from(bytes.len()).expect("argument length fits u32");
        log.write_all(&length.to_le_bytes())
            .expect("write argument length");
        log.write_all(bytes).expect("write argument");
    }
    log.write_all(&END_INVOCATION.to_le_bytes())
        .expect("write invocation delimiter");
}
