use sha2::{Digest, Sha256};
use thiserror::Error;
use zeroize::Zeroize;

pub const MAX_PLAINTEXT_BYTES: usize = 1024 * 1024;
pub const MAX_PROTECTED_BYTES: usize = MAX_PLAINTEXT_BYTES + 64 * 1024;
const MAGIC: &[u8; 8] = b"WSLDPA01";
const DIGEST_BYTES: usize = 32;
const HEADER_BYTES: usize = MAGIC.len() + DIGEST_BYTES;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum EnvelopeError {
    #[error("input exceeds the 1 MiB limit")]
    InputTooLarge,
    #[error("protected envelope is truncated")]
    Truncated,
    #[error("protected envelope has an unexpected format")]
    InvalidFormat,
    #[error("protected envelope integrity check failed")]
    Integrity,
}

pub fn wrap(plaintext: &[u8]) -> Result<Vec<u8>, EnvelopeError> {
    if plaintext.len() > MAX_PLAINTEXT_BYTES {
        return Err(EnvelopeError::InputTooLarge);
    }

    let mut envelope = Vec::with_capacity(HEADER_BYTES + plaintext.len());
    envelope.extend_from_slice(MAGIC);
    envelope.extend_from_slice(&Sha256::digest(plaintext));
    envelope.extend_from_slice(plaintext);
    Ok(envelope)
}

pub fn unwrap(mut envelope: Vec<u8>) -> Result<Vec<u8>, EnvelopeError> {
    if envelope.len() < HEADER_BYTES {
        envelope.zeroize();
        return Err(EnvelopeError::Truncated);
    }
    if &envelope[..MAGIC.len()] != MAGIC {
        envelope.zeroize();
        return Err(EnvelopeError::InvalidFormat);
    }

    let payload_length = envelope.len() - HEADER_BYTES;
    if payload_length > MAX_PLAINTEXT_BYTES {
        envelope.zeroize();
        return Err(EnvelopeError::InputTooLarge);
    }

    let digest_offset = MAGIC.len();
    let payload_offset = digest_offset + DIGEST_BYTES;
    let actual_digest = Sha256::digest(&envelope[payload_offset..]);
    if envelope[digest_offset..payload_offset] != actual_digest[..] {
        envelope.zeroize();
        return Err(EnvelopeError::Integrity);
    }

    // Keep the original length until zeroization; split_off would leave a
    // plaintext copy in the original allocation's spare capacity.
    let payload = envelope[payload_offset..].to_vec();
    envelope.zeroize();
    Ok(payload)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_round_trips_binary_data() {
        let plaintext = b"binary\0with\nnewlines\r\nand\xffbytes";
        assert_eq!(unwrap(wrap(plaintext).unwrap()).unwrap(), plaintext);
    }

    #[test]
    fn envelope_rejects_tampering() {
        let mut envelope = wrap(b"secret").unwrap();
        *envelope.last_mut().unwrap() ^= 1;
        assert_eq!(unwrap(envelope), Err(EnvelopeError::Integrity));
    }

    #[test]
    fn envelope_rejects_oversized_input() {
        let input = vec![0u8; MAX_PLAINTEXT_BYTES + 1];
        assert_eq!(wrap(&input), Err(EnvelopeError::InputTooLarge));
    }
}
