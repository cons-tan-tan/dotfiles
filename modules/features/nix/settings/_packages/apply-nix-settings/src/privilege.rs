use std::ffi::CString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use crate::error::{AppError, Result};
use crate::filesystem::parent_or_current;

pub fn needs_elevation(target: &Path) -> Result<bool> {
    let mut directory = parent_or_current(target);
    loop {
        match fs::metadata(directory) {
            Ok(metadata) => {
                if !metadata.is_dir() {
                    return Err(AppError::new(format!(
                        "apply-nix-settings: target ancestor is not a directory: {}",
                        directory.display()
                    )));
                }
                return Ok(!has_access(directory, libc::W_OK | libc::X_OK)?);
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                let parent = parent_or_current(directory);
                if parent == directory {
                    return Err(AppError::new(
                        "apply-nix-settings: cannot find an existing target ancestor",
                    ));
                }
                directory = parent;
            }
            Err(error) => return Err(AppError::io("inspect", directory, error)),
        }
    }
}

pub fn ensure_executable(path: &Path) -> Result<()> {
    let metadata = fs::metadata(path).map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: target requires root, and sudo is not available: {}: {error}",
            path.display()
        ))
    })?;
    if !metadata.is_file() || !has_access(path, libc::X_OK)? {
        return Err(AppError::new(format!(
            "apply-nix-settings: target requires root, and sudo is not available: {}",
            path.display()
        )));
    }
    Ok(())
}

fn has_access(path: &Path, mode: libc::c_int) -> Result<bool> {
    let path = CString::new(path.as_os_str().as_bytes()).map_err(|_| {
        AppError::new(format!(
            "apply-nix-settings: path contains a null byte: {}",
            path.display()
        ))
    })?;
    // SAFETY: CString supplies a valid nul-terminated path for the duration of
    // the access call.
    Ok(unsafe { libc::access(path.as_ptr(), mode) } == 0)
}
