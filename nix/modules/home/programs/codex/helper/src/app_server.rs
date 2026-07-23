use std::path::Path;
use std::time::{Duration, Instant};

use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::error::{AppError, Result};
use crate::hook_state::HooksListResponse;
use crate::process::{ManagedProcess, OutputEvent, ReceiveError, ShutdownReport};

const RESPONSE_TIMEOUT: Duration = Duration::from_secs(10);

pub fn fetch_hooks_list(codex_bin: &Path, cwd: &Path) -> Result<HooksListResponse> {
    fetch_hooks_list_with_timeout(codex_bin, cwd, RESPONSE_TIMEOUT)
}

pub fn fetch_hooks_list_with_timeout(
    codex_bin: &Path,
    cwd: &Path,
    timeout: Duration,
) -> Result<HooksListResponse> {
    if !codex_bin.is_absolute() {
        return Err(AppError::new(format!(
            "codex-config-helper: --codex-bin must be an absolute path: {}",
            codex_bin.display()
        )));
    }

    let mut process = ManagedProcess::spawn(codex_bin)?;
    let operation = run_protocol(&mut process, cwd, timeout);
    let cleanup = process.shutdown();
    finish(operation, cleanup)
}

fn run_protocol(
    process: &mut ManagedProcess,
    cwd: &Path,
    timeout: Duration,
) -> Result<HooksListResponse> {
    let cwd = cwd.to_str().ok_or_else(|| {
        AppError::new(format!(
            "codex-config-helper: cwd is not valid UTF-8: {}",
            cwd.display()
        ))
    })?;
    process.send(&json!({
        "method": "initialize",
        "id": 1,
        "params": {
            "clientInfo": {
                "name": "dotfiles",
                "title": "dotfiles",
                "version": "0",
            },
            "capabilities": {
                "experimentalApi": true,
            },
        },
    }))?;
    let _: Value = read_response(process, 1, timeout)?;

    process.send(&json!({"method": "initialized", "params": {}}))?;
    process.send(&json!({
        "method": "hooks/list",
        "id": 2,
        "params": {
            "cwds": [cwd],
        },
    }))?;
    read_response(process, 2, timeout)
}

fn read_response<T: DeserializeOwned>(
    process: &mut ManagedProcess,
    request_id: u64,
    timeout: Duration,
) -> Result<T> {
    let deadline = Instant::now() + timeout;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return Err(AppError::new(format!(
                "codex-config-helper: timed out waiting for codex app-server response {request_id}"
            )));
        }

        let event = match process.receive(remaining) {
            Ok(event) => event,
            Err(ReceiveError::Timeout) => {
                return Err(AppError::new(format!(
                    "codex-config-helper: timed out waiting for codex app-server response {request_id}"
                )));
            }
            Err(ReceiveError::Disconnected) => return eof_error(process, request_id),
        };

        let frame = match event {
            OutputEvent::Frame(frame) => frame,
            OutputEvent::FrameTooLarge => {
                return Err(AppError::new(format!(
                    "codex-config-helper: codex app-server response exceeded the frame limit while waiting for {request_id}"
                )));
            }
            OutputEvent::Eof => return eof_error(process, request_id),
            OutputEvent::ReadError(error) => {
                return Err(AppError::new(format!(
                    "codex-config-helper: cannot read codex app-server response: {error}"
                )));
            }
        };

        let value: Value = match serde_json::from_slice(&frame) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let object = value.as_object().ok_or_else(|| {
            AppError::new(format!(
                "codex-config-helper: codex app-server emitted a non-object JSON frame while waiting for {request_id}"
            ))
        })?;

        let Some(id) = object.get("id").and_then(Value::as_u64) else {
            continue;
        };
        if id != request_id {
            continue;
        }
        // JSON-RPC uses independent request-id spaces in each direction. A
        // same-id server request is not a response to this client request.
        if object.contains_key("method") {
            continue;
        }

        let has_result = object.contains_key("result");
        let has_error = object.contains_key("error");
        if has_result == has_error {
            return Err(AppError::new(format!(
                "codex-config-helper: malformed codex app-server response {request_id}: expected exactly one of result or error"
            )));
        }
        if has_error {
            return Err(rpc_error(request_id, &object["error"]));
        }

        return serde_json::from_value(object["result"].clone()).map_err(|error| {
            AppError::new(format!(
                "codex-config-helper: malformed codex app-server result {request_id}: {error}"
            ))
        });
    }
}

fn rpc_error(request_id: u64, value: &Value) -> AppError {
    let code = value.get("code").and_then(Value::as_i64);
    let message = value.get("message").and_then(Value::as_str);
    match (code, message) {
        (Some(code), Some(message)) => AppError::new(format!(
            "codex-config-helper: codex app-server response {request_id} failed ({code}): {message}"
        )),
        _ => AppError::new(format!(
            "codex-config-helper: malformed error in codex app-server response {request_id}"
        )),
    }
}

fn eof_error<T>(process: &mut ManagedProcess, request_id: u64) -> Result<T> {
    match process.try_status()? {
        Some(status) if !status.success() => Err(AppError::new(format!(
            "codex-config-helper: codex app-server exited with {status} before response {request_id}"
        ))),
        _ => Err(AppError::new(format!(
            "codex-config-helper: codex app-server reached EOF before response {request_id}"
        ))),
    }
}

fn finish<T>(operation: Result<T>, cleanup: Result<ShutdownReport>) -> Result<T> {
    match (operation, cleanup) {
        (Ok(value), Ok(_)) => Ok(value),
        (Ok(_), Err(cleanup_error)) => Err(cleanup_error),
        (Err(error), Ok(report)) => {
            let stderr = report.stderr_tail.trim();
            let natural_status = if !report.terminated_by_client && !report.status.success() {
                format!("; child_status={}", report.status)
            } else {
                String::new()
            };
            if stderr.is_empty() {
                Err(AppError::new(format!("{error}{natural_status}")))
            } else {
                Err(AppError::new(format!(
                    "{error}{natural_status}; stderr={stderr}"
                )))
            }
        }
        (Err(error), Err(cleanup_error)) => Err(AppError::new(format!(
            "{error}; additionally failed to clean up codex app-server: {cleanup_error}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rpc_error_uses_only_code_and_message() {
        let error = rpc_error(
            2,
            &json!({
                "code": -32000,
                "message": "failed",
                "data": "must not be copied",
            }),
        );
        let message = error.to_string();
        assert!(message.contains("-32000"));
        assert!(message.contains("failed"));
        assert!(!message.contains("must not be copied"));
    }
}
