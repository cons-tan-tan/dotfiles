use std::process::ExitCode;

fn main() -> ExitCode {
    match aws_config_helper::cli::parse(std::env::args_os().skip(1)) {
        Ok(command) => match aws_config_helper::app::execute(command) {
            Ok(status) => ExitCode::from(status),
            Err(error) => {
                eprintln!("{error}");
                ExitCode::FAILURE
            }
        },
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
