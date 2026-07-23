use std::ffi::OsString;
use std::io;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

pub fn exec(program: &Path, arguments: &[OsString]) -> io::Error {
    Command::new(program).args(arguments).exec()
}
