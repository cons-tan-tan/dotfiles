use crate::report::{Diagnostic, FileEvidence, Severity, sanitize_log_text, sha256};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};
use url::Url;

pub const MAX_LSP_MESSAGE_BYTES: usize = 8 * 1024 * 1024;
const MAX_LSP_HEADER_LINE_BYTES: usize = 8 * 1024;
const MAX_LSP_HEADER_LINES: usize = 32;
const MAX_READ_FILE_BYTES: u64 = 4 * 1024 * 1024;
const MAX_STDERR_BYTES: usize = 64 * 1024;
const MAX_NODE_INSPECTION_OUTPUT_BYTES: u64 = 1024 * 1024;

#[derive(Debug)]
pub struct NodeRuntime {
    pub executable: PathBuf,
    pub version: String,
    permission_flag: &'static str,
    pub permission_model_restricts_network: bool,
}

pub fn inspect_node(
    requested: Option<&Path>,
    temporary_home: &Path,
    timeout: Duration,
) -> Result<NodeRuntime, String> {
    let executable = resolve_executable(requested.unwrap_or_else(|| Path::new("node")))?;
    let mut version_command = clean_command(&executable, temporary_home);
    version_command.arg("--version");
    let version_output =
        command_output_with_timeout(&mut version_command, timeout, "Node.js version check")?;
    if !version_output.status.success() {
        return Err(format!(
            "Node.js version check failed at {}",
            executable.display()
        ));
    }
    let raw_version = String::from_utf8(version_output.stdout)
        .map_err(|_| "Node.js returned a non-UTF-8 version".to_owned())?;
    let version = raw_version.trim().trim_start_matches('v').to_owned();
    let major = version
        .split('.')
        .next()
        .and_then(|value| value.parse::<u64>().ok())
        .ok_or_else(|| format!("unrecognized Node.js version: {version}"))?;
    if major < 24 {
        return Err(format!("Node.js 24 or newer is required; found {version}"));
    }

    let mut help_command = clean_command(&executable, temporary_home);
    help_command.arg("--help");
    let help =
        command_output_with_timeout(&mut help_command, timeout, "Node.js capability inspection")?;
    if !help.status.success() {
        return Err(format!(
            "Node.js capability inspection failed at {}",
            executable.display()
        ));
    }
    let help_text = String::from_utf8_lossy(&help.stdout);
    let permission_flag = select_permission_flag(&help_text)?;
    Ok(NodeRuntime {
        executable,
        version,
        permission_flag,
        permission_model_restricts_network: help_text.contains("--allow-net"),
    })
}

fn select_permission_flag(help: &str) -> Result<&'static str, String> {
    if help.contains("--permission") {
        Ok("--permission")
    } else {
        Err("Node.js does not provide the stable Permission Model required by gha-diag".to_owned())
    }
}

fn resolve_executable(requested: &Path) -> Result<PathBuf, String> {
    if requested.components().count() > 1 || requested.is_absolute() {
        return requested.canonicalize().map_err(|error| {
            format!("cannot resolve executable {}: {error}", requested.display())
        });
    }
    let path =
        std::env::var_os("PATH").ok_or_else(|| "PATH is not set; use --node PATH".to_owned())?;
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(requested);
        if candidate.is_file() {
            return candidate.canonicalize().map_err(|error| {
                format!("cannot resolve executable {}: {error}", candidate.display())
            });
        }
    }
    Err(format!(
        "cannot find {} in PATH; use --node PATH",
        requested.display()
    ))
}

fn clean_command(executable: &Path, temporary_home: &Path) -> Command {
    let mut command = Command::new(executable);
    command.env_clear();
    command.env("HOME", temporary_home);
    command.env("TMPDIR", temporary_home);
    command.env("TMP", temporary_home);
    command.env("TEMP", temporary_home);
    for name in ["LANG", "LC_ALL", "LC_CTYPE", "TZ"] {
        if let Some(value) = std::env::var_os(name) {
            command.env(name, value);
        }
    }
    command
}

fn command_output_with_timeout(
    command: &mut Command,
    timeout: Duration,
    description: &str,
) -> Result<Output, String> {
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command
        .spawn()
        .map_err(|error| format!("cannot start {description}: {error}"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| format!("cannot capture {description} stdout"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| format!("cannot capture {description} stderr"))?;
    let stdout_reader = spawn_limited_reader(stdout);
    let stderr_reader = spawn_limited_reader(stderr);
    let deadline = Instant::now()
        .checked_add(timeout)
        .ok_or_else(|| format!("{description} timeout is too large"))?;

    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("{description} timed out"));
            }
            Err(error) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("cannot wait for {description}: {error}"));
            }
        }
    };
    let stdout = receive_limited_output(stdout_reader, deadline, description, "stdout")?;
    let stderr = receive_limited_output(stderr_reader, deadline, description, "stderr")?;
    if stdout.len() as u64 > MAX_NODE_INSPECTION_OUTPUT_BYTES
        || stderr.len() as u64 > MAX_NODE_INSPECTION_OUTPUT_BYTES
    {
        return Err(format!("{description} output exceeds the 1 MiB limit"));
    }
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

fn spawn_limited_reader(reader: impl Read + Send + 'static) -> mpsc::Receiver<io::Result<Vec<u8>>> {
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let _ = sender.send(read_limited(reader));
    });
    receiver
}

fn receive_limited_output(
    receiver: mpsc::Receiver<io::Result<Vec<u8>>>,
    deadline: Instant,
    description: &str,
    stream: &str,
) -> Result<Vec<u8>, String> {
    receiver
        .recv_timeout(deadline.saturating_duration_since(Instant::now()))
        .map_err(|_| format!("{description} {stream} capture timed out"))?
        .map_err(|error| format!("cannot read {description} {stream}: {error}"))
}

fn read_limited(reader: impl Read) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader
        .take(MAX_NODE_INSPECTION_OUTPUT_BYTES + 1)
        .read_to_end(&mut bytes)?;
    Ok(bytes)
}

pub struct Client {
    child: Child,
    writer: mpsc::SyncSender<(Value, mpsc::Sender<Result<(), String>>)>,
    receiver: mpsc::Receiver<Result<Value, String>>,
    stderr: Arc<Mutex<Vec<u8>>>,
    root: PathBuf,
    deadline_duration: Duration,
    read_dependencies: BTreeMap<String, String>,
    read_dependency_error: Option<String>,
}

impl Client {
    pub fn spawn(
        runtime: &NodeRuntime,
        bundle: &Path,
        root: &Path,
        temporary_home: &Path,
        timeout: Duration,
        max_old_space_size_mib: u64,
    ) -> Result<Self, String> {
        let mut command = clean_command(&runtime.executable, temporary_home);
        command
            .arg(format!("--max-old-space-size={max_old_space_size_mib}"))
            .arg(runtime.permission_flag)
            .arg(bundle)
            .arg("--stdio")
            .current_dir(temporary_home)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }

        let mut child = command
            .spawn()
            .map_err(|error| format!("cannot start actions language server: {error}"))?;
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| "cannot open language server stdin".to_owned())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "cannot open language server stdout".to_owned())?;
        let stderr_pipe = child
            .stderr
            .take()
            .ok_or_else(|| "cannot open language server stderr".to_owned())?;

        let (writer, write_requests) =
            mpsc::sync_channel::<(Value, mpsc::Sender<Result<(), String>>)>(1);
        thread::spawn(move || {
            while let Ok((value, acknowledgement)) = write_requests.recv() {
                let result = write_message(&mut stdin, &value)
                    .map_err(|error| format!("cannot write to language server: {error}"));
                let failed = result.is_err();
                let _ = acknowledgement.send(result);
                if failed {
                    break;
                }
            }
        });

        let (sender, receiver) = mpsc::channel();
        thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                match read_message(&mut reader) {
                    Ok(Some(message)) => {
                        if sender.send(Ok(message)).is_err() {
                            break;
                        }
                    }
                    Ok(None) => {
                        let _ = sender.send(Err("language server closed stdout".to_owned()));
                        break;
                    }
                    Err(error) => {
                        let _ =
                            sender.send(Err(format!("invalid language server output: {error}")));
                        break;
                    }
                }
            }
        });

        let stderr = Arc::new(Mutex::new(Vec::new()));
        let captured_stderr = Arc::clone(&stderr);
        thread::spawn(move || {
            let mut stderr_pipe = stderr_pipe;
            let mut buffer = [0_u8; 4096];
            loop {
                let count = match stderr_pipe.read(&mut buffer) {
                    Ok(0) | Err(_) => break,
                    Ok(count) => count,
                };
                if let Ok(mut destination) = captured_stderr.lock() {
                    let remaining = MAX_STDERR_BYTES.saturating_sub(destination.len());
                    destination.extend_from_slice(&buffer[..count.min(remaining)]);
                }
            }
        });

        let canonical_root = root
            .canonicalize()
            .map_err(|error| format!("cannot resolve repository root: {error}"))?;
        Ok(Self {
            child,
            writer,
            receiver,
            stderr,
            root: canonical_root,
            deadline_duration: timeout,
            read_dependencies: BTreeMap::new(),
            read_dependency_error: None,
        })
    }

    pub fn initialize(
        &mut self,
        enable_all_experimental_features: bool,
        disabled_experimental_features: &[String],
    ) -> Result<(), String> {
        let root_uri = Url::from_directory_path(&self.root)
            .map_err(|_| {
                format!(
                    "cannot convert repository root to URI: {}",
                    self.root.display()
                )
            })?
            .to_string();
        let mut experimental_features = serde_json::Map::new();
        experimental_features.insert(
            "all".to_owned(),
            Value::Bool(enable_all_experimental_features),
        );
        for feature in disabled_experimental_features {
            experimental_features.insert(feature.clone(), Value::Bool(false));
        }
        self.send(json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": null,
                "rootUri": root_uri,
                "capabilities": {
                    "workspace": { "workspaceFolders": true }
                },
                "workspaceFolders": [{ "uri": root_uri, "name": "workspace" }],
                "initializationOptions": {
                    "experimentalFeatures": experimental_features,
                    "repos": [{
                        "id": 0,
                        "owner": "local",
                        "name": "workspace",
                        "organizationOwned": false,
                        "workspaceUri": root_uri
                    }]
                }
            }
        }))?;
        self.wait_for_response(1)?;
        self.send(json!({ "jsonrpc": "2.0", "method": "initialized", "params": {} }))
    }

    pub fn diagnose(&mut self, file: &Path, text: &str) -> Result<Vec<Diagnostic>, String> {
        let uri = Url::from_file_path(file)
            .map_err(|_| {
                format!(
                    "cannot convert GitHub Actions file path to URI: {}",
                    file.display()
                )
            })?
            .to_string();
        self.send(json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {
                "textDocument": {
                    "uri": uri,
                    "languageId": "yaml.ghactions",
                    "version": 1,
                    "text": text
                }
            }
        }))?;

        let deadline = self.deadline()?;
        let diagnostics = loop {
            let message = self.receive_until(deadline)?;
            if self.handle_request(&message)? {
                continue;
            }
            if message.get("method").and_then(Value::as_str)
                != Some("textDocument/publishDiagnostics")
            {
                continue;
            }
            let params = message
                .get("params")
                .ok_or_else(|| "diagnostics notification has no params".to_owned())?;
            if params.get("uri").and_then(Value::as_str) != Some(uri.as_str()) {
                continue;
            }
            break parse_diagnostics(&self.root, file, params)?;
        };

        self.send(json!({
            "jsonrpc": "2.0",
            "method": "textDocument/didClose",
            "params": { "textDocument": { "uri": uri } }
        }))?;
        Ok(diagnostics)
    }

    pub fn shutdown(&mut self) -> Result<(), String> {
        self.send(json!({ "jsonrpc": "2.0", "id": 2, "method": "shutdown", "params": null }))?;
        self.wait_for_response(2)?;
        self.send(json!({ "jsonrpc": "2.0", "method": "exit", "params": null }))?;
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            match self.child.try_wait() {
                Ok(Some(status)) if status.success() => return Ok(()),
                Ok(Some(status)) => {
                    return Err(self.with_stderr(format!("language server exited with {status}")));
                }
                Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
                Ok(None) => {
                    let _ = self.child.kill();
                    let _ = self.child.wait();
                    return Err(
                        self.with_stderr("language server did not exit after shutdown".to_owned())
                    );
                }
                Err(error) => return Err(format!("cannot wait for language server: {error}")),
            }
        }
    }

    fn wait_for_response(&mut self, id: i64) -> Result<Value, String> {
        let deadline = self.deadline()?;
        loop {
            let message = self.receive_until(deadline)?;
            if self.handle_request(&message)? {
                continue;
            }
            if message.get("id").and_then(Value::as_i64) == Some(id) {
                if let Some(error) = message.get("error") {
                    return Err(format!("language server request failed: {error}"));
                }
                return Ok(message.get("result").cloned().unwrap_or(Value::Null));
            }
        }
    }

    fn receive_until(&mut self, deadline: Instant) -> Result<Value, String> {
        let timeout = deadline.saturating_duration_since(Instant::now());
        if timeout.is_zero() {
            let _ = self.child.kill();
            return Err(self.with_stderr("language server timed out".to_owned()));
        }
        match self.receiver.recv_timeout(timeout) {
            Ok(Ok(message)) => Ok(message),
            Ok(Err(error)) => Err(self.with_stderr(error)),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let _ = self.child.kill();
                Err(self.with_stderr("language server timed out".to_owned()))
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                Err(self.with_stderr("language server reader stopped".to_owned()))
            }
        }
    }

    fn handle_request(&mut self, message: &Value) -> Result<bool, String> {
        let Some(method) = message.get("method").and_then(Value::as_str) else {
            return Ok(false);
        };
        let Some(id) = message.get("id").cloned() else {
            return Ok(false);
        };
        if method == "actions/readFile" {
            let result = message
                .get("params")
                .and_then(|params| params.get("path"))
                .and_then(Value::as_str)
                .and_then(|path| self.read_file(path).ok());
            self.send(json!({ "jsonrpc": "2.0", "id": id, "result": result }))?;
            if let Some(error) = &self.read_dependency_error {
                return Err(error.clone());
            }
        } else if method == "client/registerCapability" || method == "client/unregisterCapability" {
            self.send(json!({ "jsonrpc": "2.0", "id": id, "result": null }))?;
        } else {
            self.send(json!({
                "jsonrpc": "2.0",
                "id": id,
                "error": { "code": -32601, "message": format!("unsupported server request: {method}") }
            }))?;
        }
        Ok(true)
    }

    fn read_file(&mut self, raw_uri: &str) -> Result<String, String> {
        let uri = Url::parse(raw_uri).map_err(|error| format!("invalid file URI: {error}"))?;
        if uri.scheme() != "file" {
            return Err("only file URIs are supported".to_owned());
        }
        let requested = uri
            .to_file_path()
            .map_err(|_| "cannot convert file URI to path".to_owned())?;
        let canonical = requested
            .canonicalize()
            .map_err(|error| format!("cannot resolve requested file: {error}"))?;
        if !canonical.starts_with(&self.root) {
            return Err("requested file escapes repository root".to_owned());
        }
        let metadata = fs::metadata(&canonical)
            .map_err(|error| format!("cannot inspect requested file: {error}"))?;
        if !metadata.is_file() || metadata.len() > MAX_READ_FILE_BYTES {
            return Err("requested file is not a permitted regular file".to_owned());
        }
        let extension = canonical
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or_default();
        if !extension.eq_ignore_ascii_case("yml") && !extension.eq_ignore_ascii_case("yaml") {
            return Err("requested file is not YAML".to_owned());
        }
        let bytes =
            fs::read(&canonical).map_err(|error| format!("cannot read requested file: {error}"))?;
        if bytes.len() as u64 > MAX_READ_FILE_BYTES {
            let error =
                "requested YAML file grew beyond the size limit while being read".to_owned();
            self.read_dependency_error = Some(error.clone());
            return Err(error);
        }
        let hash = sha256(&bytes);
        let text = String::from_utf8(bytes)
            .map_err(|_| "requested YAML file is not valid UTF-8".to_owned())?;
        let display = canonical
            .strip_prefix(&self.root)
            .unwrap_or(&canonical)
            .to_string_lossy()
            .replace('\\', "/");
        if let Some(previous) = self.read_dependencies.get(&display) {
            if previous != &hash {
                let error =
                    format!("read dependency changed while diagnostics were running: {display}");
                self.read_dependency_error = Some(error.clone());
                return Err(error);
            }
        } else {
            self.read_dependencies.insert(display, hash);
        }
        Ok(text)
    }

    pub fn read_dependencies(&self) -> Vec<FileEvidence> {
        self.read_dependencies
            .iter()
            .map(|(path, hash)| FileEvidence {
                path: path.clone(),
                sha256: hash.clone(),
            })
            .collect()
    }

    fn deadline(&self) -> Result<Instant, String> {
        Instant::now()
            .checked_add(self.deadline_duration)
            .ok_or_else(|| "language server timeout is too large".to_owned())
    }

    fn send(&mut self, value: Value) -> Result<(), String> {
        let (acknowledge, completed) = mpsc::channel();
        self.writer
            .send((value, acknowledge))
            .map_err(|_| self.with_stderr("language server writer stopped".to_owned()))?;
        match completed.recv_timeout(self.deadline_duration) {
            Ok(Ok(())) => Ok(()),
            Ok(Err(error)) => Err(self.with_stderr(error)),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let _ = self.child.kill();
                Err(self.with_stderr("language server write timed out".to_owned()))
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                Err(self.with_stderr("language server writer stopped".to_owned()))
            }
        }
    }

    fn with_stderr(&self, message: String) -> String {
        let stderr = self
            .stderr
            .lock()
            .ok()
            .map(|bytes| sanitize_log_text(String::from_utf8_lossy(&bytes).trim()))
            .unwrap_or_default();
        if stderr.is_empty() {
            message
        } else {
            format!("{message}: {stderr}")
        }
    }
}

impl Drop for Client {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

fn parse_diagnostics(root: &Path, file: &Path, params: &Value) -> Result<Vec<Diagnostic>, String> {
    let display = file
        .strip_prefix(root)
        .unwrap_or(file)
        .to_string_lossy()
        .replace('\\', "/");
    let values = params
        .get("diagnostics")
        .and_then(Value::as_array)
        .ok_or_else(|| "diagnostics notification has no diagnostics array".to_owned())?;
    values
        .iter()
        .map(|value| {
            let range = value
                .get("range")
                .ok_or_else(|| "diagnostic has no range".to_owned())?;
            let start = range
                .get("start")
                .ok_or_else(|| "diagnostic has no start position".to_owned())?;
            let end = range
                .get("end")
                .ok_or_else(|| "diagnostic has no end position".to_owned())?;
            let position = |object: &Value, name: &str| {
                object
                    .get(name)
                    .and_then(Value::as_u64)
                    .ok_or_else(|| format!("diagnostic position has no {name}"))
            };
            let severity = match value.get("severity").and_then(Value::as_u64).unwrap_or(1) {
                2 => Severity::Warning,
                3 => Severity::Information,
                4 => Severity::Hint,
                _ => Severity::Error,
            };
            let code = value.get("code").map(|code| match code {
                Value::String(value) => value.clone(),
                other => other.to_string(),
            });
            Ok(Diagnostic {
                file: display.clone(),
                severity,
                message: value
                    .get("message")
                    .and_then(Value::as_str)
                    .ok_or_else(|| "diagnostic has no message".to_owned())?
                    .to_owned(),
                line: position(start, "line")? + 1,
                column: position(start, "character")? + 1,
                end_line: position(end, "line")? + 1,
                end_column: position(end, "character")? + 1,
                code,
                source: value
                    .get("source")
                    .and_then(Value::as_str)
                    .map(str::to_owned),
            })
        })
        .collect()
}

fn write_message(writer: &mut impl Write, value: &Value) -> io::Result<()> {
    let bytes = serde_json::to_vec(value).map_err(io::Error::other)?;
    write!(writer, "Content-Length: {}\r\n\r\n", bytes.len())?;
    writer.write_all(&bytes)?;
    writer.flush()
}

fn read_message(reader: &mut impl BufRead) -> io::Result<Option<Value>> {
    let mut content_length = None;
    for _ in 0..MAX_LSP_HEADER_LINES {
        let mut bytes = Vec::new();
        let read = reader
            .take((MAX_LSP_HEADER_LINE_BYTES + 1) as u64)
            .read_until(b'\n', &mut bytes)?;
        if read == 0 {
            return if content_length.is_none() {
                Ok(None)
            } else {
                Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "EOF in LSP headers",
                ))
            };
        }
        if bytes.len() > MAX_LSP_HEADER_LINE_BYTES || !bytes.ends_with(b"\n") {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "LSP header line exceeds size limit",
            ));
        }
        let line = std::str::from_utf8(&bytes)
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "non-UTF-8 LSP header"))?;
        if line == "\r\n" || line == "\n" {
            let length = content_length.ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "missing Content-Length")
            })?;
            if length > MAX_LSP_MESSAGE_BYTES {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "LSP message exceeds size limit",
                ));
            }
            let mut body = vec![0; length];
            reader.read_exact(&mut body)?;
            return serde_json::from_slice(&body)
                .map(Some)
                .map_err(io::Error::other);
        }
        if let Some(value) = line.strip_prefix("Content-Length:") {
            content_length = Some(value.trim().parse::<usize>().map_err(|_| {
                io::Error::new(io::ErrorKind::InvalidData, "invalid Content-Length")
            })?);
        }
    }
    Err(io::Error::new(
        io::ErrorKind::InvalidData,
        "too many LSP header lines",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_and_writes_lsp_frames() {
        let value = json!({"jsonrpc": "2.0", "id": 1, "result": {}});
        let mut bytes = Vec::new();
        write_message(&mut bytes, &value).expect("write frame");
        let mut reader = BufReader::new(bytes.as_slice());
        assert_eq!(read_message(&mut reader).expect("read frame"), Some(value));
    }

    #[test]
    fn rejects_oversized_lsp_frames_before_allocation() {
        let input = format!("Content-Length: {}\r\n\r\n", MAX_LSP_MESSAGE_BYTES + 1);
        let error =
            read_message(&mut BufReader::new(input.as_bytes())).expect_err("must reject frame");
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn rejects_oversized_lsp_headers() {
        let input = vec![b'x'; MAX_LSP_HEADER_LINE_BYTES + 1];
        let error =
            read_message(&mut BufReader::new(input.as_slice())).expect_err("must reject header");
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn selects_the_available_node_permission_flag() {
        assert_eq!(
            select_permission_flag("  --permission  enable permissions"),
            Ok("--permission")
        );
        assert!(select_permission_flag("  --experimental-permission  enable permissions").is_err());
        assert!(select_permission_flag("--help").is_err());
    }

    #[test]
    fn node_preflight_commands_are_bounded() {
        let mut command = Command::new(std::env::current_exe().expect("current test executable"));
        command
            .args([
                "--exact",
                "language_server::tests::node_preflight_timeout_helper",
                "--nocapture",
            ])
            .env("GHA_DIAG_PREFLIGHT_TIMEOUT_HELPER", "1");

        let error = command_output_with_timeout(
            &mut command,
            Duration::from_millis(50),
            "test Node.js preflight",
        )
        .expect_err("preflight must time out");
        assert!(error.contains("timed out"));
    }

    #[test]
    fn node_preflight_timeout_helper() {
        if std::env::var_os("GHA_DIAG_PREFLIGHT_TIMEOUT_HELPER").is_some() {
            thread::sleep(Duration::from_secs(5));
        }
    }
}
