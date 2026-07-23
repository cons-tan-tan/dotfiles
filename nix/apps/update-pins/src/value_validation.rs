use base64::Engine as _;
use base64::engine::general_purpose::STANDARD;

use crate::error::UpdateError;

pub(crate) fn validate_sri_hash(label: &str, hash: &str) -> Result<(), UpdateError> {
    let Some(encoded) = hash.strip_prefix("sha256-") else {
        return Err(UpdateError::message(format!(
            "{label}: expected a sha256 SRI hash"
        )));
    };
    if encoded.len() > 64 {
        return Err(UpdateError::message(format!(
            "{label}: sha256 SRI hash is too long"
        )));
    }
    let decoded = STANDARD.decode(encoded).map_err(|_| {
        UpdateError::message(format!("{label}: expected a valid base64 sha256 SRI hash"))
    })?;
    if decoded.len() != 32 {
        return Err(UpdateError::message(format!(
            "{label}: expected a 32-byte sha256 SRI hash"
        )));
    }
    Ok(())
}

pub(crate) fn validate_https_url(label: &str, url: &str) -> Result<(), UpdateError> {
    let authority = url
        .strip_prefix("https://")
        .and_then(|rest| rest.split(['/', '?', '#']).next());
    if url.len() <= 4096
        && authority.is_some_and(|authority| {
            !authority.is_empty() && authority.contains('.') && !authority.contains('@')
        })
        && !url.contains('\\')
        && !url.chars().any(char::is_whitespace)
        && !url.chars().any(char::is_control)
    {
        Ok(())
    } else {
        Err(UpdateError::message(format!(
            "{label}: expected a non-empty HTTPS URL"
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::{validate_https_url, validate_sri_hash};

    #[test]
    fn sri_hash_requires_exact_sha256_shape() {
        assert!(
            validate_sri_hash(
                "hash",
                "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            )
            .is_ok()
        );
        for invalid in [
            "",
            "sha256-invalid",
            "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "sha256-YQ==",
        ] {
            assert!(validate_sri_hash("hash", invalid).is_err(), "{invalid}");
        }
    }

    #[test]
    fn urls_are_https_and_bounded_to_one_token() {
        assert!(validate_https_url("url", "https://example.invalid/path").is_ok());
        for invalid in [
            "",
            "http://example.invalid",
            "https://",
            "https:///path",
            "https://example.invalid/\nsecret",
        ] {
            assert!(validate_https_url("url", invalid).is_err(), "{invalid:?}");
        }
    }
}
