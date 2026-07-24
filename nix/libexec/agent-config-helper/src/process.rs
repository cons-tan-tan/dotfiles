use std::collections::VecDeque;
use std::io::{Read, Write};
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::error::{AppError, Result};

pub(crate) const STDOUT_FRAME_LIMIT: usize = 1024 * 1024;
const STDERR_TAIL_LIMIT: usize = 8 * 1024;
const STDOUT_QUEUE_DEPTH: usize = 64;
const READER_JOIN_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Debug)]
pub(crate) enum OutputEvent {
    Frame(Vec<u8>),
    FrameTooLarge,
    Eof,
    ReadError(String),
}

#[derive(Debug)]
pub(crate) enum ReceiveError {
    Timeout,
    Disconnected,
}

pub(crate) struct ShutdownReport {
    pub status: ExitStatus,
    pub terminated_by_client: bool,
    pub stderr_tail: String,
}

pub(crate) struct ManagedProcess {
    child: Child,
    stdin: Option<ChildStdin>,
    stdout_events: Option<Receiver<OutputEvent>>,
    stdout_thread: Option<JoinHandle<()>>,
    stderr_thread: Option<JoinHandle<()>>,
    stderr_tail: Arc<Mutex<VecDeque<u8>>>,
    finished: bool,
}

impl ManagedProcess {
    pub(crate) fn spawn(codex_bin: &Path) -> Result<Self> {
        let mut command = Command::new(codex_bin);
        command
            .args(["app-server", "--listen", "stdio://"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command.process_group(0);
        let mut child = command
            .spawn()
            .map_err(|error| AppError::io("start codex app-server", codex_bin, error))?;

        let stdin = child.stdin.take().ok_or_else(|| {
            AppError::new("agent-config-helper: codex app-server stdin is unavailable")
        })?;
        let stdout = child.stdout.take().ok_or_else(|| {
            AppError::new("agent-config-helper: codex app-server stdout is unavailable")
        })?;
        let stderr = child.stderr.take().ok_or_else(|| {
            AppError::new("agent-config-helper: codex app-server stderr is unavailable")
        })?;

        let (stdout_tx, stdout_rx) = mpsc::sync_channel(STDOUT_QUEUE_DEPTH);
        let stdout_thread = thread::spawn(move || drain_stdout(stdout, stdout_tx));

        let stderr_tail = Arc::new(Mutex::new(VecDeque::with_capacity(STDERR_TAIL_LIMIT)));
        let stderr_buffer = Arc::clone(&stderr_tail);
        let stderr_thread = thread::spawn(move || drain_stderr(stderr, &stderr_buffer));

        Ok(Self {
            child,
            stdin: Some(stdin),
            stdout_events: Some(stdout_rx),
            stdout_thread: Some(stdout_thread),
            stderr_thread: Some(stderr_thread),
            stderr_tail,
            finished: false,
        })
    }

    pub(crate) fn send(&mut self, message: &impl Serialize) -> Result<()> {
        let bytes = serde_json::to_vec(message)?;
        let stdin = self.stdin.as_mut().ok_or_else(|| {
            AppError::new("agent-config-helper: codex app-server stdin is unavailable")
        })?;
        stdin.write_all(&bytes).map_err(|error| {
            AppError::new(format!(
                "agent-config-helper: cannot write codex app-server request: {error}"
            ))
        })?;
        stdin.write_all(b"\n").map_err(|error| {
            AppError::new(format!(
                "agent-config-helper: cannot terminate codex app-server request: {error}"
            ))
        })?;
        stdin.flush().map_err(|error| {
            AppError::new(format!(
                "agent-config-helper: cannot flush codex app-server request: {error}"
            ))
        })
    }

    pub(crate) fn receive(
        &self,
        timeout: Duration,
    ) -> std::result::Result<OutputEvent, ReceiveError> {
        let Some(events) = self.stdout_events.as_ref() else {
            return Err(ReceiveError::Disconnected);
        };
        match events.recv_timeout(timeout) {
            Ok(event) => Ok(event),
            Err(RecvTimeoutError::Timeout) => Err(ReceiveError::Timeout),
            Err(RecvTimeoutError::Disconnected) => Err(ReceiveError::Disconnected),
        }
    }

    pub(crate) fn try_status(&mut self) -> Result<Option<ExitStatus>> {
        self.child.try_wait().map_err(|error| {
            AppError::new(format!(
                "agent-config-helper: cannot inspect codex app-server status: {error}"
            ))
        })
    }

    pub(crate) fn shutdown(&mut self) -> Result<ShutdownReport> {
        if self.finished {
            return Err(AppError::new(
                "agent-config-helper: codex app-server was already reaped",
            ));
        }

        // Closing stdin first gives the child a chance to observe that the
        // protocol connection ended before it is forcibly terminated.
        drop(self.stdin.take());

        let (status, terminated_by_client, group_error) = match self.child.try_wait() {
            Ok(Some(status)) => (
                status,
                false,
                terminate_process_group(self.child.id()).err(),
            ),
            Ok(None) => {
                let group_error = terminate_process_group(self.child.id()).err();
                if group_error.is_some() {
                    let _ = self.child.kill();
                }
                (
                    self.child.wait().map_err(|error| {
                        AppError::new(format!(
                            "agent-config-helper: cannot reap codex app-server: {error}"
                        ))
                    })?,
                    true,
                    group_error,
                )
            }
            Err(error) => {
                let _ = terminate_process_group(self.child.id());
                let _ = self.child.kill();
                let _ = self.child.wait();
                return Err(AppError::new(format!(
                    "agent-config-helper: cannot inspect codex app-server status: {error}"
                )));
            }
        };

        // A bounded stdout queue can leave the reader blocked in send. Drop
        // the receiver only after the process group is gone. Bound the joins
        // too, because a descendant can deliberately leave the group while
        // retaining an inherited pipe.
        drop(self.stdout_events.take());
        self.finished = true;
        join_reader("stdout", self.stdout_thread.take(), READER_JOIN_TIMEOUT)?;
        join_reader("stderr", self.stderr_thread.take(), READER_JOIN_TIMEOUT)?;
        if let Some(error) = group_error {
            return Err(AppError::new(format!(
                "agent-config-helper: cannot terminate codex app-server process group: {error}"
            )));
        }
        let tail = self
            .stderr_tail
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .iter()
            .copied()
            .collect::<Vec<_>>();
        Ok(ShutdownReport {
            status,
            terminated_by_client,
            stderr_tail: String::from_utf8_lossy(&tail).into_owned(),
        })
    }
}

fn terminate_process_group(child_id: u32) -> std::io::Result<()> {
    // SAFETY: spawn places the child in a process group whose id is the child
    // pid. killpg targets only that dedicated group.
    if unsafe { libc::killpg(child_id as libc::pid_t, libc::SIGKILL) } == 0 {
        return Ok(());
    }
    let error = std::io::Error::last_os_error();
    if error.raw_os_error() == Some(libc::ESRCH) {
        Ok(())
    } else {
        Err(error)
    }
}

fn join_reader(name: &str, handle: Option<JoinHandle<()>>, timeout: Duration) -> Result<()> {
    let Some(handle) = handle else {
        return Ok(());
    };
    let deadline = Instant::now() + timeout;
    while !handle.is_finished() && Instant::now() < deadline {
        thread::sleep(Duration::from_millis(5));
    }
    if !handle.is_finished() {
        drop(handle);
        return Err(AppError::new(format!(
            "agent-config-helper: timed out waiting for codex app-server {name} reader"
        )));
    }
    handle.join().map_err(|_| {
        AppError::new(format!(
            "agent-config-helper: codex app-server {name} reader panicked"
        ))
    })
}

impl Drop for ManagedProcess {
    fn drop(&mut self) {
        if !self.finished {
            let _ = self.shutdown();
        }
    }
}

fn drain_stdout(mut stdout: impl Read, sender: SyncSender<OutputEvent>) {
    let mut input = [0_u8; 8192];
    let mut frame = Vec::new();
    let mut oversized = false;

    loop {
        match stdout.read(&mut input) {
            Ok(0) => {
                if oversized {
                    if sender.send(OutputEvent::FrameTooLarge).is_err() {
                        return;
                    }
                } else if !frame.is_empty() {
                    if frame.last() == Some(&b'\r') {
                        frame.pop();
                    }
                    if sender.send(OutputEvent::Frame(frame)).is_err() {
                        return;
                    }
                }
                let _ = sender.send(OutputEvent::Eof);
                return;
            }
            Ok(count) => {
                for byte in &input[..count] {
                    if *byte == b'\n' {
                        let event = if oversized {
                            OutputEvent::FrameTooLarge
                        } else {
                            if frame.last() == Some(&b'\r') {
                                frame.pop();
                            }
                            OutputEvent::Frame(std::mem::take(&mut frame))
                        };
                        if sender.send(event).is_err() {
                            return;
                        }
                        frame.clear();
                        oversized = false;
                    } else if !oversized {
                        if frame.len() < STDOUT_FRAME_LIMIT {
                            frame.push(*byte);
                        } else {
                            frame.clear();
                            oversized = true;
                        }
                    }
                }
            }
            Err(error) => {
                let _ = sender.send(OutputEvent::ReadError(error.to_string()));
                return;
            }
        }
    }
}

fn drain_stderr(mut stderr: impl Read, tail: &Arc<Mutex<VecDeque<u8>>>) {
    let mut input = [0_u8; 8192];
    loop {
        match stderr.read(&mut input) {
            Ok(0) => return,
            Ok(count) => {
                let mut tail = tail.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
                for byte in &input[..count] {
                    if tail.len() == STDERR_TAIL_LIMIT {
                        tail.pop_front();
                    }
                    tail.push_back(*byte);
                }
            }
            Err(_) => return,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn stdout_reader_splits_coalesced_frames() {
        let (sender, receiver) = mpsc::sync_channel(8);
        drain_stdout(Cursor::new(b"one\ntwo\r\nthree".to_vec()), sender);

        assert!(matches!(
            receiver.recv().unwrap(),
            OutputEvent::Frame(value) if value == b"one"
        ));
        assert!(matches!(
            receiver.recv().unwrap(),
            OutputEvent::Frame(value) if value == b"two"
        ));
        assert!(matches!(
            receiver.recv().unwrap(),
            OutputEvent::Frame(value) if value == b"three"
        ));
        assert!(matches!(receiver.recv().unwrap(), OutputEvent::Eof));
    }

    #[test]
    fn stdout_reader_rejects_an_oversized_frame_without_retaining_it() {
        let mut input = vec![b'x'; STDOUT_FRAME_LIMIT + 1];
        input.extend_from_slice(b"\n{}\n");
        let (sender, receiver) = mpsc::sync_channel(8);
        drain_stdout(Cursor::new(input), sender);

        assert!(matches!(
            receiver.recv().unwrap(),
            OutputEvent::FrameTooLarge
        ));
        assert!(matches!(
            receiver.recv().unwrap(),
            OutputEvent::Frame(value) if value == b"{}"
        ));
    }

    #[test]
    fn stderr_reader_keeps_only_the_tail_while_draining_every_byte() {
        let tail = Arc::new(Mutex::new(VecDeque::new()));
        let input = vec![b'a'; STDERR_TAIL_LIMIT + 32];
        drain_stderr(Cursor::new(input), &tail);
        assert_eq!(tail.lock().unwrap().len(), STDERR_TAIL_LIMIT);
    }
}
