use std::io;
use std::path::PathBuf;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum UpdateError {
    #[error("failed to execute {program}: {source}")]
    Spawn {
        program: String,
        #[source]
        source: io::Error,
    },

    #[error("{program} exceeded {seconds} second execution limit")]
    CommandTimedOut { program: String, seconds: u64 },

    #[error("{command} failed with status {status}: {stderr}")]
    CommandFailed {
        command: String,
        status: String,
        stderr: String,
    },

    #[error("{command} returned non-UTF-8 output")]
    NonUtf8Output { command: String },

    #[error("failed to access {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("invalid JSON in {path}: {source}")]
    InvalidJson {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },

    #[error("{path}: expected a JSON object")]
    ExpectedObject { path: PathBuf },

    #[error("{path}: missing or invalid string field {field}")]
    InvalidStringField { path: PathBuf, field: String },

    #[error("update-pins: managed files already have {kind} changes; refusing to overwrite them")]
    DirtyManagedFiles { kind: &'static str },

    #[error("update-pins: another update-pins process is already running")]
    AlreadyRunning,

    #[error("update-pins: transaction has already been finalized")]
    TransactionFinalized,

    #[error("update-pins: managed path is outside the repository: {0}")]
    UnsafeManagedPath(PathBuf),

    #[error("update-pins: refusing to modify unmanaged path: {0}")]
    UnmanagedPath(PathBuf),

    #[error("update-pins: rollback failed: {0}")]
    Rollback(String),

    #[error(
        "update-pins: rollback failed while restoring managed files ({restore}) and releasing the transaction lock ({unlock})"
    )]
    RollbackAndUnlock {
        restore: Box<UpdateError>,
        unlock: Box<UpdateError>,
    },

    #[error("update-pins: rollback failed while releasing the transaction lock: {unlock}")]
    RollbackUnlock { unlock: Box<UpdateError> },

    #[error("{operation}; rollback also failed: {rollback}")]
    OperationAndRollback {
        operation: Box<UpdateError>,
        rollback: Box<UpdateError>,
    },

    #[error("{0}")]
    Message(String),
}

impl UpdateError {
    pub fn io(path: impl Into<PathBuf>, source: io::Error) -> Self {
        Self::Io {
            path: path.into(),
            source,
        }
    }

    pub fn message(message: impl Into<String>) -> Self {
        Self::Message(message.into())
    }
}
