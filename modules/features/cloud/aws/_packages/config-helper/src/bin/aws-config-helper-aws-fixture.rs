use std::ffi::OsString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

fn main() {
    let arguments = std::env::args_os().collect::<Vec<_>>();
    write_arguments(&arguments[1..]);
    let mode = std::env::var("AWS_CONFIG_HELPER_FIXTURE_MODE").unwrap_or_default();
    if mode == "fail" {
        std::process::exit(7);
    }
    if mode == "wait" {
        let ready = required_path("AWS_CONFIG_HELPER_FIXTURE_READY");
        let release = required_path("AWS_CONFIG_HELPER_FIXTURE_RELEASE");
        fs::write(&ready, b"ready").expect("write fixture ready marker");
        wait_for_path(&release);
    }

    let config_path = required_path("AWS_CONFIG_FILE");
    let mut config = fs::read_to_string(&config_path).expect("read AWS config candidate");
    let eol = if config.contains("\r\n") {
        "\r\n"
    } else if config.contains('\r') {
        "\r"
    } else {
        "\n"
    };
    if !config.ends_with(['\r', '\n']) {
        config.push_str(eol);
    }
    match mode.as_str() {
        "success" | "wait" => {
            config.push_str("login_session = fixture-session");
            config.push_str(eol);
        }
        "prompt-region" => {
            config.push_str("region = ap-northeast-1");
            config.push_str(eol);
            config.push_str("login_session = fixture-session");
            config.push_str(eol);
        }
        "forbidden" => {
            config = config.replace("output = json", "output = yaml");
            config.push_str("login_session = fixture-session");
            config.push_str(eol);
        }
        "malformed" => {
            config.push_str("malformed");
            config.push_str(eol);
        }
        other => panic!("unknown fixture mode: {other}"),
    }
    fs::write(config_path, config).expect("write AWS config candidate");
}

fn write_arguments(arguments: &[OsString]) {
    let Some(path) = std::env::var_os("AWS_CONFIG_HELPER_FIXTURE_ARGV") else {
        return;
    };
    let mut bytes = Vec::new();
    for argument in arguments {
        bytes.extend_from_slice(argument.as_os_str().as_bytes());
        bytes.push(0);
    }
    fs::write(path, bytes).expect("write fixture argv");
}

fn required_path(variable: &str) -> PathBuf {
    std::env::var_os(variable)
        .map(PathBuf::from)
        .unwrap_or_else(|| panic!("missing {variable}"))
}

fn wait_for_path(path: &Path) {
    let deadline = Instant::now() + Duration::from_secs(10);
    while !path.exists() {
        assert!(Instant::now() < deadline, "timed out waiting for release");
        std::thread::sleep(Duration::from_millis(10));
    }
}
