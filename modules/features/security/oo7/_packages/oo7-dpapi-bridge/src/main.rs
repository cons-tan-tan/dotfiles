use std::path::PathBuf;
use std::process::ExitCode;

use oo7_dpapi_bridge::{PrepareConfig, default_data_home, prepare};

const USAGE: &str = "Usage: oo7-dpapi-bridge HELPER BLOB\n";

#[tokio::main]
async fn main() -> ExitCode {
    let mut args = std::env::args_os().skip(1);
    let (helper, blob) = match (args.next(), args.next(), args.next()) {
        (Some(argument), None, None) if argument == "--help" || argument == "-h" => {
            print!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        (Some(helper), Some(blob), None) => (PathBuf::from(helper), PathBuf::from(blob)),
        _ => {
            eprint!("{USAGE}");
            return ExitCode::from(2);
        }
    };
    let data_home = match default_data_home() {
        Ok(path) => path,
        Err(error) => {
            eprintln!("oo7-dpapi-bridge: {error}");
            return ExitCode::FAILURE;
        }
    };

    match prepare(&PrepareConfig {
        helper,
        blob,
        data_home,
    })
    .await
    {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("oo7-dpapi-bridge: {error}");
            ExitCode::FAILURE
        }
    }
}
