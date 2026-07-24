use std::env;
use std::fs::{self, File};
use std::io::{self, BufRead, Write};
use std::os::fd::FromRawFd;
use std::process::{self, Command, Stdio};
use std::thread;
use std::time::Duration;

use serde_json::{Value, json};

#[allow(clippy::zombie_processes)]
fn main() {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    if arguments == ["__pipe-holder"] {
        thread::sleep(Duration::from_secs(60));
        return;
    }
    if arguments != ["app-server", "--listen", "stdio://"] {
        eprintln!("unexpected argv: {arguments:?}");
        process::exit(91);
    }

    let invoked_path = env::args_os().next().expect("fixture argv[0]");
    let invoked_path = std::path::PathBuf::from(invoked_path);
    let mode = invoked_path
        .file_name()
        .and_then(|name| name.to_str())
        .expect("UTF-8 fixture mode")
        .to_string();
    fs::write(
        invoked_path.with_extension("pid"),
        process::id().to_string(),
    )
    .expect("write pid");

    let stdin = io::stdin();
    let mut input = stdin.lock();
    let mut output = io::stdout().lock();
    let initialize = read_message(&mut input);
    require_request(&initialize, "initialize", Some(1));

    if mode == "grandchild-pipe-holder" {
        let executable = env::current_exe().expect("fixture path");
        let grandchild = spawn_pipe_holding_grandchild(&executable);
        fs::write(
            invoked_path.with_extension("grandchild.pid"),
            grandchild.id().to_string(),
        )
        .expect("write grandchild pid");
    }

    match mode.as_str() {
        "eof" => return,
        "nonzero" => {
            eprintln!("fixture-nonzero-marker");
            process::exit(23);
        }
        "partial-stall" => {
            output.write_all(br#"{"id":1,"result":"#).unwrap();
            output.flush().unwrap();
            thread::sleep(Duration::from_secs(60));
            return;
        }
        "oversized-frame" => {
            output.write_all(&vec![b'x'; 1024 * 1024 + 1]).unwrap();
            output.write_all(b"\n").unwrap();
            output.flush().unwrap();
            thread::sleep(Duration::from_secs(60));
            return;
        }
        "malformed-envelope" => {
            write_json(
                &mut output,
                &json!({
                    "id": 1,
                    "result": {},
                    "error": {"code": -1, "message": "also error"},
                }),
            );
            thread::sleep(Duration::from_secs(60));
            return;
        }
        "non-object-json" => {
            output.write_all(b"42\n").unwrap();
            output.flush().unwrap();
            thread::sleep(Duration::from_secs(60));
            return;
        }
        "close-after-initialize" => {
            drop(input);
            // SAFETY: this fixture owns descriptor 0 and intentionally closes
            // it before responding to make the next client write deterministic.
            unsafe {
                drop(File::from_raw_fd(0));
            }
            write_json(&mut output, &json!({"id": 1, "result": {}}));
            // Small client writes can already be buffered when the close is
            // observed, so exit to make EOF the other valid transport error.
            return;
        }
        "noisy-single-write" => {
            output
                .write_all(
                    b"not-json\n{\"method\":\"server/notice\",\"params\":{}}\n\
                      {\"id\":999,\"result\":{}}\n{\"id\":1,\"result\":{}}\n",
                )
                .unwrap();
            output.flush().unwrap();
        }
        "same-id-server-request" => {
            output
                .write_all(
                    b"{\"id\":1,\"method\":\"server/request\",\"params\":{}}\n\
                      {\"id\":1,\"result\":{}}\n",
                )
                .unwrap();
            output.flush().unwrap();
        }
        "stderr-flood" | "stderr-flood-error" => {
            let mut stderr = io::stderr().lock();
            stderr.write_all(&vec![b'a'; 256 * 1024]).unwrap();
            stderr.write_all(b"fixture-stderr-tail-marker\n").unwrap();
            stderr.flush().unwrap();
            write_json(&mut output, &json!({"id": 1, "result": {}}));
        }
        _ => write_json(&mut output, &json!({"id": 1, "result": {}})),
    }

    let initialized = read_message(&mut input);
    require_request(&initialized, "initialized", None);
    let hooks_list = read_message(&mut input);
    require_request(&hooks_list, "hooks/list", Some(2));
    assert!(
        hooks_list["params"]["cwds"]
            .as_array()
            .is_some_and(|cwds| cwds.len() == 1 && cwds[0].as_str().is_some()),
        "hooks/list must contain one cwd"
    );

    if mode == "rpc-error" || mode == "stderr-flood-error" {
        write_json(
            &mut output,
            &json!({
                "id": 2,
                "error": {
                    "code": -32000,
                    "message": "fixture rpc failure",
                    "data": "do not expose this field",
                },
            }),
        );
        thread::sleep(Duration::from_secs(60));
        return;
    }

    let response = json!({
        "id": 2,
        "result": {
            "data": [{
                "cwd": hooks_list["params"]["cwds"][0],
                "hooks": [{
                    "key": "/tmp/build-home/.codex/hooks.json:session_start:1:0",
                    "eventName": "sessionStart",
                    "command": "herdr-command",
                    "currentHash": "sha256:from-fixture",
                }],
                "warnings": [],
                "errors": [],
            }],
        },
    });
    if mode == "noisy-single-write" {
        let response = serde_json::to_vec(&response).unwrap();
        output
            .write_all(b"{\"method\":\"another/notice\",\"params\":{}}\nnot-json\n")
            .unwrap();
        output.write_all(&response).unwrap();
        output.write_all(b"\n").unwrap();
        output.flush().unwrap();
    } else {
        write_json(&mut output, &response);
    }

    // The client owns lifecycle termination. Remaining alive after a valid
    // response proves that it closes, kills, and waits instead of relying on
    // natural fixture exit.
    thread::sleep(Duration::from_secs(60));
}

#[allow(clippy::zombie_processes)]
fn spawn_pipe_holding_grandchild(executable: &std::path::Path) -> process::Child {
    // Intentionally do not wait: this fixture models an app-server that
    // abandons a descendant holding inherited stdout/stderr pipes.
    Command::new(executable)
        .arg("__pipe-holder")
        .stdin(Stdio::null())
        .spawn()
        .expect("spawn pipe-holding grandchild")
}

fn read_message(input: &mut impl BufRead) -> Value {
    let mut line = String::new();
    let count = input.read_line(&mut line).expect("read request");
    assert_ne!(count, 0, "unexpected request EOF");
    serde_json::from_str(&line).expect("request JSON")
}

fn require_request(value: &Value, method: &str, id: Option<u64>) {
    assert_eq!(value["method"], method);
    match id {
        Some(id) => assert_eq!(value["id"], id),
        None => assert!(value.get("id").is_none()),
    }
    assert!(value.get("jsonrpc").is_none());
}

fn write_json(output: &mut impl Write, value: &Value) {
    serde_json::to_writer(&mut *output, value).unwrap();
    output.write_all(b"\n").unwrap();
    output.flush().unwrap();
}
