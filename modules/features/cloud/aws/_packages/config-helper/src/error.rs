use std::fmt;
use std::io;
use std::path::Path;

#[derive(Debug)]
pub struct AppError {
    message: String,
    committed: bool,
}

impl AppError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            committed: false,
        }
    }

    pub fn io(operation: &str, path: &Path, source: io::Error) -> Self {
        Self::new(format!(
            "aws-config-helper: {operation} {}: {source}",
            path.display()
        ))
    }

    pub fn committed(operation: &str, path: &Path, source: io::Error) -> Self {
        Self {
            message: format!(
                "aws-config-helper: config was committed, but {operation} {} failed: {source}",
                path.display()
            ),
            committed: true,
        }
    }

    #[must_use]
    pub fn is_committed(&self) -> bool {
        self.committed
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for AppError {}

pub type Result<T> = std::result::Result<T, AppError>;
