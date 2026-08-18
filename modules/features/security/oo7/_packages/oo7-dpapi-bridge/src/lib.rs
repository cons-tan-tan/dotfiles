use std::fs::{self, File};
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};

use oo7::{Secret, file::UnlockedKeyring};
use tempfile::NamedTempFile;
use thiserror::Error;
use zeroize::Zeroizing;

pub const MASTER_BYTES: usize = 64;
const MAX_PROTECTED_BYTES: usize = 1024 * 1024;
const SENTINEL_LABEL: &str = "WSL DPAPI keyring verifier";
const SENTINEL_SECRET: &[u8] = b"io.github.cons-tan-tan.oo7-dpapi.verifier.v1";
const SENTINEL_ATTRIBUTES: [(&str, &str); 2] = [
    ("xdg:schema", "io.github.cons-tan-tan.oo7-dpapi"),
    ("purpose", "dpapi-master-verifier-v1"),
];

#[derive(Clone, Debug)]
pub struct PrepareConfig {
    pub helper: PathBuf,
    pub blob: PathBuf,
    pub data_home: PathBuf,
}

impl PrepareConfig {
    pub fn login_keyring(&self) -> PathBuf {
        self.data_home.join("keyrings/v1/login.keyring")
    }

    pub fn legacy_login_keyring(&self) -> PathBuf {
        self.data_home.join("keyrings/login.keyring")
    }
}

#[derive(Debug, Error)]
pub enum PrepareError {
    #[error("the DPAPI blob is missing while an oo7 Login keyring already exists: {0}")]
    MissingBlobForExistingKeyring(PathBuf),
    #[error("a legacy oo7 Login keyring must be migrated before DPAPI initialization: {0}")]
    LegacyKeyring(PathBuf),
    #[error("DPAPI helper {operation} failed with {status}: {diagnostic}")]
    HelperFailed {
        operation: &'static str,
        status: ExitStatus,
        diagnostic: String,
    },
    #[error(
        "DPAPI helper returned an invalid {actual}-byte master secret; expected {MASTER_BYTES} bytes"
    )]
    InvalidMasterLength { actual: usize },
    #[error("DPAPI helper returned an invalid protected blob")]
    InvalidProtectedBlob,
    #[error("the oo7 DPAPI verifier item has unexpected contents")]
    SentinelMismatch,
    #[error("security state path is not a regular file: {0}")]
    NonRegularFile(PathBuf),
    #[error("could not execute DPAPI helper for {operation}: {source}")]
    HelperIo {
        operation: &'static str,
        #[source]
        source: io::Error,
    },
    #[error("could not initialize the oo7 Login keyring: {0}")]
    Keyring(#[from] oo7::file::Error),
    #[error(transparent)]
    Random(#[from] getrandom::Error),
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error("could not persist protected blob at {path}: {source}")]
    PersistBlob {
        path: PathBuf,
        #[source]
        source: tempfile::PersistError,
    },
}

pub async fn prepare(config: &PrepareConfig) -> Result<(), PrepareError> {
    let keyring_path = config.login_keyring();
    let blob_exists = regular_file_exists(&config.blob)?;
    let keyring_exists = regular_file_exists(&keyring_path)?;

    if keyring_exists && !blob_exists {
        return Err(PrepareError::MissingBlobForExistingKeyring(keyring_path));
    }
    if !keyring_exists && entry_exists(&config.legacy_login_keyring())? {
        return Err(PrepareError::LegacyKeyring(config.legacy_login_keyring()));
    }

    let master = if blob_exists {
        fs::set_permissions(&config.blob, fs::Permissions::from_mode(0o600))?;
        unprotect_master(&config.helper, &config.blob)?
    } else {
        let mut master = Zeroizing::new(vec![0u8; MASTER_BYTES]);
        getrandom::fill(master.as_mut_slice())?;
        let protected = protect_master(&config.helper, &master)?;
        persist_blob(&config.blob, &protected)?;
        master
    };

    ensure_sentinel(&keyring_path, &master).await
}

fn entry_exists(path: &Path) -> io::Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

fn regular_file_exists(path: &Path) -> Result<bool, PrepareError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_file() => Ok(true),
        Ok(_) => Err(PrepareError::NonRegularFile(path.to_path_buf())),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

fn helper_failure(operation: &'static str, status: ExitStatus, stderr: &[u8]) -> PrepareError {
    let diagnostic = String::from_utf8_lossy(&stderr[..stderr.len().min(4096)])
        .trim()
        .to_owned();
    PrepareError::HelperFailed {
        operation,
        status,
        diagnostic: if diagnostic.is_empty() {
            "no diagnostic".to_owned()
        } else {
            diagnostic
        },
    }
}

fn unprotect_master(helper: &Path, blob: &Path) -> Result<Zeroizing<Vec<u8>>, PrepareError> {
    let input = File::open(blob)?;
    let output = Command::new(helper)
        .arg("unprotect")
        .stdin(Stdio::from(input))
        .output()
        .map_err(|source| PrepareError::HelperIo {
            operation: "unprotect",
            source,
        })?;
    let stdout = Zeroizing::new(output.stdout);
    if !output.status.success() {
        return Err(helper_failure("unprotect", output.status, &output.stderr));
    }
    if stdout.len() != MASTER_BYTES {
        return Err(PrepareError::InvalidMasterLength {
            actual: stdout.len(),
        });
    }
    Ok(stdout)
}

fn protect_master(helper: &Path, master: &[u8]) -> Result<Vec<u8>, PrepareError> {
    let mut child = Command::new(helper)
        .arg("protect")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|source| PrepareError::HelperIo {
            operation: "protect",
            source,
        })?;

    let mut stdin = child.stdin.take().ok_or_else(|| PrepareError::HelperIo {
        operation: "protect",
        source: io::Error::other("helper stdin was not piped"),
    })?;
    if let Err(source) = stdin.write_all(master).and_then(|()| stdin.flush()) {
        drop(stdin);
        let _ = child.kill();
        let _ = child.wait();
        return Err(PrepareError::HelperIo {
            operation: "protect",
            source,
        });
    }
    drop(stdin);

    let output = child
        .wait_with_output()
        .map_err(|source| PrepareError::HelperIo {
            operation: "protect",
            source,
        })?;
    if !output.status.success() {
        return Err(helper_failure("protect", output.status, &output.stderr));
    }
    if output.stdout.is_empty() || output.stdout.len() > MAX_PROTECTED_BYTES {
        return Err(PrepareError::InvalidProtectedBlob);
    }
    Ok(output.stdout)
}

fn persist_blob(path: &Path, protected: &[u8]) -> Result<(), PrepareError> {
    let parent = path.parent().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "DPAPI blob path has no parent")
    })?;
    fs::create_dir_all(parent)?;
    fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;

    let mut temporary = NamedTempFile::new_in(parent)?;
    temporary
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    temporary.write_all(protected)?;
    temporary.as_file().sync_all()?;
    temporary
        .persist_noclobber(path)
        .map_err(|source| PrepareError::PersistBlob {
            path: path.to_path_buf(),
            source,
        })?;
    File::open(parent)?.sync_all()?;
    Ok(())
}

async fn ensure_sentinel(keyring_path: &Path, master: &[u8]) -> Result<(), PrepareError> {
    let parent = keyring_path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "oo7 keyring path has no parent",
        )
    })?;
    fs::create_dir_all(parent)?;
    fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;

    let keyring = UnlockedKeyring::load(keyring_path, Secret::blob(master)).await?;
    if let Some(item) = keyring.lookup_item(&SENTINEL_ATTRIBUTES).await? {
        if item.as_unlocked().secret().as_bytes() != SENTINEL_SECRET {
            return Err(PrepareError::SentinelMismatch);
        }
        fs::set_permissions(keyring_path, fs::Permissions::from_mode(0o600))?;
        return Ok(());
    }

    keyring
        .create_item(
            SENTINEL_LABEL,
            &SENTINEL_ATTRIBUTES,
            Secret::blob(SENTINEL_SECRET),
            false,
        )
        .await?;
    fs::set_permissions(keyring_path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

pub fn default_data_home() -> Result<PathBuf, PrepareError> {
    if let Some(path) = std::env::var_os("XDG_DATA_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
    {
        return Ok(path);
    }
    let home = std::env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))?;
    Ok(home.join(".local/share"))
}
