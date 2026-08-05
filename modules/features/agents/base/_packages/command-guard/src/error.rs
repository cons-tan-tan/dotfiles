use std::path::PathBuf;

#[derive(Debug, thiserror::Error)]
pub enum GuardError {
    #[error("failed to read policy {path}: {source}")]
    ReadPolicy {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("invalid policy JSON: {0}")]
    PolicyJson(#[from] serde_json::Error),
    #[error("invalid command guard policy: {0}")]
    Policy(String),
    #[error("failed to initialize shell parser: {0}")]
    Parser(String),
    #[error("failed to load Shellfirm catalog: {0}")]
    Shellfirm(String),
    #[error("invalid command options: {0}")]
    Options(String),
    #[error("invalid hook input: {0}")]
    HookInput(String),
    #[error("failed to read hook input: {0}")]
    ReadInput(#[source] std::io::Error),
}

pub type Result<T> = std::result::Result<T, GuardError>;
