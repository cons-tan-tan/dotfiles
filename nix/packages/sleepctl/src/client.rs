use crate::model::HEARTBEAT_EVERY_MS;
use crate::protocol::{
    Envelope, Event, Reply, Request, ServerMessage, read_frame, require_version, write_frame,
};
use std::io;
use std::os::unix::net::UnixStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::Duration;

const SOCKET_PATH: &str = "/var/run/sleepctld.sock";
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

pub struct LeaseClient {
    lease_id: String,
    writer: Arc<Mutex<UnixStream>>,
    receiver: mpsc::Receiver<io::Result<ServerMessage>>,
    active: Arc<AtomicBool>,
}

impl LeaseClient {
    pub fn acquire(duration_ms: u64) -> io::Result<Self> {
        let mut stream = UnixStream::connect(SOCKET_PATH)?;
        stream.set_read_timeout(Some(REQUEST_TIMEOUT))?;
        stream.set_write_timeout(Some(REQUEST_TIMEOUT))?;
        write_frame(
            &mut stream,
            &Envelope::new(Request::Acquire { duration_ms }),
        )?;
        let reply = read_message(&mut stream)?;
        let lease_id = match reply {
            ServerMessage::Reply(Reply::LeaseAccepted { lease_id }) => lease_id,
            ServerMessage::Reply(Reply::Error { code, message }) => {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    format!("{code}: {message}"),
                ));
            }
            other => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("unexpected acquire response: {other:?}"),
                ));
            }
        };
        stream.set_read_timeout(None)?;

        let writer = Arc::new(Mutex::new(stream.try_clone()?));
        let (sender, receiver) = mpsc::channel();
        thread::spawn(move || {
            let mut reader = stream;
            loop {
                let result = read_message(&mut reader);
                let closed = result.is_err();
                if sender.send(result).is_err() || closed {
                    break;
                }
            }
        });

        let active = Arc::new(AtomicBool::new(true));
        start_heartbeats(Arc::clone(&writer), lease_id.clone(), Arc::clone(&active));
        Ok(Self {
            lease_id,
            writer,
            receiver,
            active,
        })
    }

    #[must_use]
    pub fn lease_id(&self) -> &str {
        &self.lease_id
    }

    pub fn try_event(&self) -> io::Result<Option<Event>> {
        loop {
            match self.receiver.try_recv() {
                Ok(Ok(ServerMessage::Event(event))) => return Ok(Some(event)),
                Ok(Ok(ServerMessage::Reply(Reply::HeartbeatAck))) => {}
                Ok(Ok(ServerMessage::Reply(Reply::Released))) => {}
                Ok(Ok(ServerMessage::Reply(Reply::Error { code, message }))) => {
                    return Err(io::Error::other(format!("{code}: {message}")));
                }
                Ok(Ok(_)) => {}
                Ok(Err(error)) => return Err(error),
                Err(mpsc::TryRecvError::Empty) => return Ok(None),
                Err(mpsc::TryRecvError::Disconnected) => {
                    return Err(io::Error::new(
                        io::ErrorKind::ConnectionAborted,
                        "daemon connection closed",
                    ));
                }
            }
        }
    }

    pub fn deactivate(&self) {
        self.active.store(false, Ordering::Relaxed);
    }

    pub fn disconnect(&self) {
        self.deactivate();
        self.shutdown();
    }

    pub fn release(&self) -> io::Result<()> {
        self.deactivate();
        let result = self.release_inner();
        self.shutdown();
        result
    }

    fn release_inner(&self) -> io::Result<()> {
        {
            let mut writer = self
                .writer
                .lock()
                .map_err(|_| io::Error::other("daemon writer lock is poisoned"))?;
            write_frame(
                &mut *writer,
                &Envelope::new(Request::Release {
                    lease_id: self.lease_id.clone(),
                }),
            )?;
        }
        loop {
            match self.receiver.recv_timeout(REQUEST_TIMEOUT) {
                Ok(Ok(ServerMessage::Reply(Reply::Released))) => return Ok(()),
                Ok(Ok(ServerMessage::Reply(Reply::HeartbeatAck))) => {}
                Ok(Ok(ServerMessage::Reply(Reply::Error { code, message }))) => {
                    return Err(io::Error::other(format!("{code}: {message}")));
                }
                Ok(Ok(ServerMessage::Event(Event::Trip { reason, .. }))) => {
                    return Err(io::Error::other(format!(
                        "safety trip while releasing lease: {reason:?}"
                    )));
                }
                Ok(Ok(_)) => {}
                Ok(Err(error)) => return Err(error),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    return Err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "timed out waiting for verified lease release",
                    ));
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    return Err(io::Error::new(
                        io::ErrorKind::ConnectionAborted,
                        "daemon closed before release acknowledgement",
                    ));
                }
            }
        }
    }

    pub fn wait_for_power_restore(&self) -> io::Result<()> {
        let result = loop {
            match self.receiver.recv_timeout(REQUEST_TIMEOUT) {
                Ok(Ok(ServerMessage::Event(Event::PowerRestored { lease_id })))
                    if lease_id == self.lease_id =>
                {
                    break Ok(());
                }
                Ok(Ok(ServerMessage::Event(Event::Trip {
                    reason: crate::model::TripReason::PowerRestoreFailed,
                    ..
                }))) => {
                    break Err(io::Error::other(
                        "daemon could not verify restoration of SleepDisabled",
                    ));
                }
                Ok(Ok(ServerMessage::Reply(Reply::HeartbeatAck))) => {}
                Ok(Ok(ServerMessage::Event(Event::Warning { .. }))) => {}
                Ok(Ok(_)) => {}
                Ok(Err(error)) => break Err(error),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    break Err(io::Error::new(
                        io::ErrorKind::TimedOut,
                        "timed out waiting for verified power restoration",
                    ));
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    break Err(io::Error::new(
                        io::ErrorKind::ConnectionAborted,
                        "daemon closed before power restoration acknowledgement",
                    ));
                }
            }
        };
        self.shutdown();
        result
    }

    fn shutdown(&self) {
        if let Ok(writer) = self.writer.lock() {
            let _ = writer.shutdown(std::net::Shutdown::Both);
        }
    }
}

impl Drop for LeaseClient {
    fn drop(&mut self) {
        if self.active.swap(false, Ordering::Relaxed)
            && let Ok(mut writer) = self.writer.lock()
        {
            let _ = write_frame(
                &mut *writer,
                &Envelope::new(Request::Release {
                    lease_id: self.lease_id.clone(),
                }),
            );
        }
        self.shutdown();
    }
}

fn start_heartbeats(writer: Arc<Mutex<UnixStream>>, lease_id: String, active: Arc<AtomicBool>) {
    thread::spawn(move || {
        while active.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_millis(HEARTBEAT_EVERY_MS));
            if !active.load(Ordering::Relaxed) {
                break;
            }
            let result = writer
                .lock()
                .map_err(|_| io::Error::other("daemon writer lock is poisoned"))
                .and_then(|mut writer| {
                    write_frame(
                        &mut *writer,
                        &Envelope::new(Request::Heartbeat {
                            lease_id: lease_id.clone(),
                        }),
                    )
                });
            if result.is_err() {
                active.store(false, Ordering::Relaxed);
                break;
            }
        }
    });
}

pub fn request(request: Request) -> io::Result<Reply> {
    let mut stream = UnixStream::connect(SOCKET_PATH)?;
    stream.set_read_timeout(Some(REQUEST_TIMEOUT))?;
    stream.set_write_timeout(Some(REQUEST_TIMEOUT))?;
    write_frame(&mut stream, &Envelope::new(request))?;
    match read_message(&mut stream)? {
        ServerMessage::Reply(reply) => Ok(reply),
        ServerMessage::Event(event) => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unexpected event: {event:?}"),
        )),
    }
}

fn read_message(stream: &mut UnixStream) -> io::Result<ServerMessage> {
    require_version(read_frame::<Envelope<ServerMessage>>(stream)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TripReason;

    fn lease_client(
        messages: impl IntoIterator<Item = ServerMessage>,
    ) -> (LeaseClient, UnixStream) {
        let (stream, peer) = UnixStream::pair().unwrap();
        let writer = Arc::new(Mutex::new(stream));
        let (sender, receiver) = mpsc::channel();
        for message in messages {
            sender.send(Ok(message)).unwrap();
        }
        drop(sender);
        (
            LeaseClient {
                lease_id: "lease-1".into(),
                writer,
                receiver,
                active: Arc::new(AtomicBool::new(false)),
            },
            peer,
        )
    }

    #[test]
    fn release_waits_for_the_verified_release_acknowledgement() {
        let (lease, mut peer) = lease_client([ServerMessage::Reply(Reply::Released)]);

        lease.release().unwrap();

        assert_eq!(
            require_version(read_frame::<Envelope<Request>>(&mut peer).unwrap()).unwrap(),
            Request::Release {
                lease_id: "lease-1".into(),
            }
        );
    }

    #[test]
    fn trip_waits_for_the_matching_power_restored_event() {
        let (lease, _peer) = lease_client([
            ServerMessage::Event(Event::Warning {
                thermal: crate::model::ThermalState::Fair,
            }),
            ServerMessage::Event(Event::PowerRestored {
                lease_id: "another-lease".into(),
            }),
            ServerMessage::Event(Event::PowerRestored {
                lease_id: "lease-1".into(),
            }),
        ]);

        lease.wait_for_power_restore().unwrap();
    }

    #[test]
    fn power_restore_failure_is_reported_as_cleanup_failure() {
        let (lease, _peer) = lease_client([ServerMessage::Event(Event::Trip {
            lease_id: "lease-1".into(),
            reason: TripReason::PowerRestoreFailed,
        })]);

        let error = lease.wait_for_power_restore().unwrap_err();
        assert!(
            error
                .to_string()
                .contains("could not verify restoration of SleepDisabled")
        );
    }
}
