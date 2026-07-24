use sleepctl::protocol::{
    Envelope, MAX_FRAME_BYTES, PROTOCOL_VERSION, Request, read_frame, require_version, write_frame,
};
use std::io::{self, Write};
use std::os::unix::net::UnixStream;
use std::thread;

#[test]
fn framed_request_crosses_a_unix_socket_without_identity_fields() {
    let (mut client, mut server) = UnixStream::pair().unwrap();
    let sender = thread::spawn(move || {
        write_frame(
            &mut client,
            &Envelope::new(Request::Acquire { duration_ms: 5_000 }),
        )
        .unwrap();
    });
    let request = require_version(read_frame::<Envelope<Request>>(&mut server).unwrap()).unwrap();
    assert_eq!(request, Request::Acquire { duration_ms: 5_000 });
    sender.join().unwrap();
}

#[test]
fn malformed_json_is_rejected() {
    let payload = b"{not-json}";
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    bytes.extend_from_slice(payload);
    let error = read_frame::<Envelope<Request>>(&mut bytes.as_slice()).unwrap_err();
    assert_eq!(error.kind(), io::ErrorKind::InvalidData);
}

#[test]
fn oversized_frame_is_rejected_before_reading_payload() {
    let mut bytes = Vec::new();
    bytes
        .write_all(&((MAX_FRAME_BYTES as u32) + 1).to_be_bytes())
        .unwrap();
    let error = read_frame::<Envelope<Request>>(&mut bytes.as_slice()).unwrap_err();
    assert_eq!(error.kind(), io::ErrorKind::InvalidData);
}

#[test]
fn unsupported_version_is_rejected() {
    let request = Envelope {
        version: PROTOCOL_VERSION + 1,
        body: Request::Status,
    };
    assert_eq!(
        require_version(request).unwrap_err().kind(),
        io::ErrorKind::InvalidData
    );
}

#[test]
fn protocol_has_no_request_that_accepts_a_command_or_pid() {
    let requests = [
        Request::Acquire { duration_ms: 1 },
        Request::Heartbeat {
            lease_id: "lease".into(),
        },
        Request::Release {
            lease_id: "lease".into(),
        },
        Request::Status,
        Request::Doctor,
        Request::StopAll,
        Request::Recover,
    ];
    for request in requests {
        let json = serde_json::to_string(&request).unwrap();
        assert!(!json.contains("command"));
        assert!(!json.contains("pid"));
        assert!(!json.contains("signal"));
        assert!(!json.contains("uid"));
    }
}
