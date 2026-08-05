use crate::model::{BatteryState, ThermalState, TripReason};
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_FRAME_BYTES: usize = 64 * 1024;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Envelope<T> {
    pub version: u16,
    pub body: T,
}

impl<T> Envelope<T> {
    #[must_use]
    pub fn new(body: T) -> Self {
        Self {
            version: PROTOCOL_VERSION,
            body,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Request {
    Acquire { duration_ms: u64 },
    Heartbeat { lease_id: String },
    Release { lease_id: String },
    Status,
    Doctor,
    StopAll,
    Recover,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Reply {
    LeaseAccepted { lease_id: String },
    HeartbeatAck,
    Released,
    Status(Status),
    Doctor(DoctorStatus),
    Stopped { leases: usize },
    Recovered,
    Error { code: String, message: String },
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    Warning {
        thermal: ThermalState,
    },
    LeaseExpired {
        lease_id: String,
    },
    LeaseRevoked {
        lease_id: String,
    },
    OperatorStopped {
        lease_id: String,
    },
    PowerRestored {
        lease_id: String,
    },
    Trip {
        lease_id: String,
        reason: TripReason,
    },
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct LeaseStatus {
    pub id: String,
    pub remaining_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Status {
    pub schema_version: u16,
    pub daemon_reachable: bool,
    pub healthy: bool,
    pub health_problem: Option<String>,
    pub thermal: Option<ThermalState>,
    pub thermal_latched: bool,
    pub battery: Option<BatteryState>,
    pub sleep_disabled: Option<bool>,
    pub foreign_state: bool,
    pub active_leases: Vec<LeaseStatus>,
    pub last_trip: Option<TripReason>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DoctorStatus {
    pub daemon_reachable: bool,
    pub daemon_healthy: bool,
    pub health_problem: Option<String>,
    pub peer_authenticated: bool,
    pub thermal_available: bool,
    pub power_commands_available: bool,
    pub state_directory_secure: bool,
    pub sleep_disabled: Option<bool>,
    pub foreign_state: bool,
    pub problems: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "kind", content = "payload", rename_all = "snake_case")]
pub enum ServerMessage {
    Reply(Reply),
    Event(Event),
}

pub fn write_frame<T: Serialize>(writer: &mut impl Write, value: &T) -> io::Result<()> {
    let payload = serde_json::to_vec(value)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    if payload.len() > MAX_FRAME_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "protocol frame exceeds 64 KiB",
        ));
    }
    let length = u32::try_from(payload.len())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "frame length overflow"))?;
    writer.write_all(&length.to_be_bytes())?;
    writer.write_all(&payload)?;
    writer.flush()
}

pub fn read_frame<T: for<'de> Deserialize<'de>>(reader: &mut impl Read) -> io::Result<T> {
    let mut header = [0_u8; 4];
    loop {
        match reader.read(&mut header[..1]) {
            Ok(0) => return Err(io::Error::from(io::ErrorKind::UnexpectedEof)),
            Ok(1) => break,
            Ok(_) => unreachable!("one-byte read returned more than one byte"),
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(error) => return Err(error),
        }
    }
    read_exact_frame_part(reader, &mut header[1..], "truncated frame header")?;
    let length = u32::from_be_bytes(header) as usize;
    if length > MAX_FRAME_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "protocol frame exceeds 64 KiB",
        ));
    }
    let mut payload = vec![0_u8; length];
    read_exact_frame_part(reader, &mut payload, "truncated frame payload")?;
    serde_json::from_slice(&payload)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
}

fn read_exact_frame_part(
    reader: &mut impl Read,
    buffer: &mut [u8],
    message: &'static str,
) -> io::Result<()> {
    reader.read_exact(buffer).map_err(|error| {
        if error.kind() == io::ErrorKind::UnexpectedEof {
            io::Error::new(io::ErrorKind::InvalidData, message)
        } else {
            error
        }
    })
}

pub fn require_version<T>(envelope: Envelope<T>) -> io::Result<T> {
    if envelope.version != PROTOCOL_VERSION {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unsupported protocol version {}", envelope.version),
        ));
    }
    Ok(envelope.body)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_preserves_request() {
        let request = Envelope::new(Request::Acquire { duration_ms: 10 });
        let mut bytes = Vec::new();
        write_frame(&mut bytes, &request).unwrap();
        assert_eq!(
            read_frame::<Envelope<Request>>(&mut bytes.as_slice()).unwrap(),
            request
        );
    }

    #[test]
    fn oversized_frame_is_rejected_before_allocation() {
        let mut bytes = ((MAX_FRAME_BYTES as u32) + 1).to_be_bytes().to_vec();
        bytes.extend_from_slice(b"{}");
        let error = read_frame::<Envelope<Request>>(&mut bytes.as_slice()).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn clean_close_and_truncated_frames_are_distinct() {
        assert_eq!(
            read_frame::<Envelope<Request>>(&mut [].as_slice())
                .unwrap_err()
                .kind(),
            io::ErrorKind::UnexpectedEof
        );
        assert_eq!(
            read_frame::<Envelope<Request>>(&mut [0, 0].as_slice())
                .unwrap_err()
                .kind(),
            io::ErrorKind::InvalidData
        );
        assert_eq!(
            read_frame::<Envelope<Request>>(&mut [0, 0, 0, 2, b'{'].as_slice())
                .unwrap_err()
                .kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn unknown_version_is_rejected() {
        let envelope = Envelope {
            version: PROTOCOL_VERSION + 1,
            body: Request::Status,
        };
        assert_eq!(
            require_version(envelope).unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }
}
