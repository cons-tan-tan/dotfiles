use std::io;
use std::process::ExitCode;

fn main() -> ExitCode {
    let stdout = io::stdout();
    let stderr = io::stderr();
    let mut stdout = stdout.lock();
    let mut stderr = stderr.lock();
    let code = nix_mutation_test::app::run(std::env::args_os().skip(1), &mut stdout, &mut stderr);
    ExitCode::from(code)
}
