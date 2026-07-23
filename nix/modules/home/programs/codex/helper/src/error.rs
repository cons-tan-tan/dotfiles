use std::fmt;
use std::path::Path;

#[derive(Debug)]
pub struct AppError {
    message: String,
}

impl AppError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    pub fn io(operation: &str, path: &Path, error: std::io::Error) -> Self {
        Self::new(format!(
            "codex-config-helper: cannot {operation} {}: {error}",
            path.display()
        ))
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.message.fmt(formatter)
    }
}

impl std::error::Error for AppError {}

impl From<serde_json::Error> for AppError {
    fn from(error: serde_json::Error) -> Self {
        Self::new(format!("codex-config-helper: invalid JSON: {error}"))
    }
}

pub type Result<T> = std::result::Result<T, AppError>;
