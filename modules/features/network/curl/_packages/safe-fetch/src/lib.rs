pub mod curl_policy;
pub mod gh_policy;
pub mod process;

use std::fmt;

#[derive(Debug, Eq, PartialEq)]
pub struct PolicyError {
    message: String,
}

impl PolicyError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for PolicyError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for PolicyError {}
