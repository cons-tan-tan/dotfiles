use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use tempfile::Builder;

use crate::error::{AppError, Result};

pub const MAX_CONFIG_BYTES: u64 = 1024 * 1024;

pub struct TargetLock {
    target: PathBuf,
    directory: PathBuf,
    _lock: File,
}

impl TargetLock {
    pub fn acquire(target: &Path) -> Result<Self> {
        let parent = parent_or_current(target);
        ensure_directory(parent)?;
        let parent_metadata = fs::symlink_metadata(parent)
            .map_err(|error| AppError::io("reinspect directory", parent, error))?;
        if parent_metadata.file_type().is_symlink() || !parent_metadata.is_dir() {
            return Err(AppError::new(format!(
                "aws-config-helper: target parent is not a real directory: {}",
                parent.display()
            )));
        }
        validate_directory_security(parent, &parent_metadata)?;
        let directory = parent
            .canonicalize()
            .map_err(|error| AppError::io("canonicalize directory", parent, error))?;
        let name = target.file_name().ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: target has no file name: {}",
                target.display()
            ))
        })?;
        let target = directory.join(name);
        validate_target(&target)?;

        let lock_path = directory.join(".aws-config-helper.lock");
        if let Ok(metadata) = fs::symlink_metadata(&lock_path)
            && !metadata.is_file()
        {
            return Err(AppError::new(format!(
                "aws-config-helper: lock path is not a regular file: {}",
                lock_path.display()
            )));
        }
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(&lock_path)
            .map_err(|error| AppError::io("open lock file", &lock_path, error))?;
        let lock_metadata = lock
            .metadata()
            .map_err(|error| AppError::io("inspect lock file", &lock_path, error))?;
        if lock_metadata.uid() != current_uid() {
            return Err(AppError::new(format!(
                "aws-config-helper: lock file is not owned by the current user: {}",
                lock_path.display()
            )));
        }
        lock.set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|error| AppError::io("set lock mode on", &lock_path, error))?;
        lock.lock()
            .map_err(|error| AppError::io("lock", &lock_path, error))?;
        validate_target(&target)?;

        Ok(Self {
            target,
            directory,
            _lock: lock,
        })
    }

    pub fn target(&self) -> &Path {
        &self.target
    }

    pub fn directory(&self) -> &Path {
        &self.directory
    }

    pub fn read(&self) -> Result<Vec<u8>> {
        read_regular_file(&self.target, true)
    }

    pub fn publish(&self, content: &[u8]) -> Result<bool> {
        if content.len() as u64 > MAX_CONFIG_BYTES {
            return Err(AppError::new(format!(
                "aws-config-helper: completed config exceeds {MAX_CONFIG_BYTES} bytes"
            )));
        }
        let current = self.read()?;
        let private_mode = fs::symlink_metadata(&self.target)
            .ok()
            .is_some_and(|metadata| metadata.mode() & 0o777 == 0o600);
        if current == content && private_mode {
            return Ok(false);
        }
        atomic_replace_with_hook(&self.target, &self.directory, content, |_| Ok(()))?;
        Ok(true)
    }
}

pub fn read_required(path: &Path) -> Result<Vec<u8>> {
    read_regular_file(path, false)
}

pub fn create_candidate(directory: &Path, content: &[u8]) -> Result<tempfile::NamedTempFile> {
    let mut candidate = Builder::new()
        .prefix(".aws-config-helper.candidate.")
        .tempfile_in(directory)
        .map_err(|error| AppError::io("create candidate in", directory, error))?;
    candidate
        .as_file_mut()
        .set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|error| AppError::io("set candidate mode on", candidate.path(), error))?;
    candidate
        .write_all(content)
        .map_err(|error| AppError::io("write candidate", candidate.path(), error))?;
    candidate
        .as_file_mut()
        .sync_all()
        .map_err(|error| AppError::io("sync candidate", candidate.path(), error))?;
    Ok(candidate)
}

fn parent_or_current(path: &Path) -> &Path {
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
}

fn ensure_directory(directory: &Path) -> Result<()> {
    match fs::symlink_metadata(directory) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() || !metadata.is_dir() {
                return Err(AppError::new(format!(
                    "aws-config-helper: target parent is not a real directory: {}",
                    directory.display()
                )));
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            fs::create_dir_all(directory)
                .map_err(|source| AppError::io("create directory", directory, source))?;
            fs::set_permissions(directory, fs::Permissions::from_mode(0o700))
                .map_err(|source| AppError::io("set directory mode on", directory, source))?;
        }
        Err(error) => return Err(AppError::io("inspect directory", directory, error)),
    }
    Ok(())
}

fn validate_directory_security(path: &Path, metadata: &fs::Metadata) -> Result<()> {
    if metadata.uid() != current_uid() {
        return Err(AppError::new(format!(
            "aws-config-helper: target parent is not owned by the current user: {}",
            path.display()
        )));
    }
    if metadata.mode() & 0o022 != 0 {
        return Err(AppError::new(format!(
            "aws-config-helper: target parent is group- or world-writable: {}",
            path.display()
        )));
    }
    Ok(())
}

fn current_uid() -> u32 {
    // SAFETY: geteuid has no preconditions and does not dereference pointers.
    unsafe { libc::geteuid() }
}

fn validate_target(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                return Err(AppError::new(format!(
                    "aws-config-helper: target must not be a symlink: {}",
                    path.display()
                )));
            }
            if !metadata.is_file() {
                return Err(AppError::new(format!(
                    "aws-config-helper: target is not a regular file: {}",
                    path.display()
                )));
            }
            if metadata.uid() != current_uid() {
                return Err(AppError::new(format!(
                    "aws-config-helper: target is not owned by the current user: {}",
                    path.display()
                )));
            }
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(AppError::io("inspect target", path, error)),
    }
    Ok(())
}

fn read_regular_file(path: &Path, allow_missing: bool) -> Result<Vec<u8>> {
    let file = match OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)
    {
        Ok(file) => file,
        Err(error) if allow_missing && error.kind() == io::ErrorKind::NotFound => {
            return Ok(Vec::new());
        }
        Err(error) => return Err(AppError::io("open", path, error)),
    };
    let metadata = file
        .metadata()
        .map_err(|error| AppError::io("inspect", path, error))?;
    if !metadata.is_file() {
        return Err(AppError::new(format!(
            "aws-config-helper: path is not a regular file: {}",
            path.display()
        )));
    }
    if metadata.len() > MAX_CONFIG_BYTES {
        return Err(AppError::new(format!(
            "aws-config-helper: config exceeds {MAX_CONFIG_BYTES} bytes: {}",
            path.display()
        )));
    }
    let mut bytes = Vec::with_capacity(metadata.len() as usize);
    file.take(MAX_CONFIG_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| AppError::io("read", path, error))?;
    if bytes.len() as u64 > MAX_CONFIG_BYTES {
        return Err(AppError::new(format!(
            "aws-config-helper: config exceeds {MAX_CONFIG_BYTES} bytes: {}",
            path.display()
        )));
    }
    Ok(bytes)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum PublishStage {
    Write,
    Sync,
    Rename,
    DirectorySync,
}

fn atomic_replace_with_hook<F>(
    target: &Path,
    directory: &Path,
    content: &[u8],
    mut before: F,
) -> Result<()>
where
    F: FnMut(PublishStage) -> io::Result<()>,
{
    let mut temporary = Builder::new()
        .prefix(".aws-config-helper.tmp.")
        .tempfile_in(directory)
        .map_err(|error| AppError::io("create temporary file in", directory, error))?;
    temporary
        .as_file_mut()
        .set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|error| AppError::io("set temporary mode on", temporary.path(), error))?;
    before(PublishStage::Write)
        .map_err(|error| AppError::io("prepare write to", temporary.path(), error))?;
    temporary
        .write_all(content)
        .map_err(|error| AppError::io("write", temporary.path(), error))?;
    before(PublishStage::Sync)
        .map_err(|error| AppError::io("prepare sync of", temporary.path(), error))?;
    temporary
        .as_file_mut()
        .sync_all()
        .map_err(|error| AppError::io("sync", temporary.path(), error))?;
    before(PublishStage::Rename)
        .map_err(|error| AppError::io("prepare rename to", target, error))?;
    temporary
        .persist(target)
        .map_err(|error| AppError::io("rename to", target, error.error))?;
    before(PublishStage::DirectorySync)
        .map_err(|error| AppError::committed("prepare directory sync for", directory, error))?;
    sync_directory(directory)
        .map_err(|error| AppError::committed("sync directory", directory, error))?;
    Ok(())
}

fn sync_directory(directory: &Path) -> io::Result<()> {
    match File::open(directory)?.sync_all() {
        Ok(()) => Ok(()),
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::InvalidInput | io::ErrorKind::Unsupported
            ) =>
        {
            Ok(())
        }
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{MetadataExt, symlink};
    use tempfile::tempdir;

    #[test]
    fn lock_reads_and_publishes_a_private_regular_file() {
        let work = tempdir().unwrap();
        let target = work.path().join("config");
        fs::write(&target, b"old").unwrap();

        let lock = TargetLock::acquire(&target).unwrap();
        assert_eq!(lock.read().unwrap(), b"old");
        assert!(lock.publish(b"new").unwrap());
        assert_eq!(fs::read(&target).unwrap(), b"new");
        assert_eq!(fs::metadata(&target).unwrap().mode() & 0o777, 0o600);
        let inode = fs::metadata(&target).unwrap().ino();
        assert!(!lock.publish(b"new").unwrap());
        assert_eq!(fs::metadata(&target).unwrap().ino(), inode);
    }

    #[test]
    fn identical_content_is_replaced_when_the_mode_is_not_private() {
        let work = tempdir().unwrap();
        let target = work.path().join("config");
        fs::write(&target, b"same").unwrap();
        fs::set_permissions(&target, fs::Permissions::from_mode(0o644)).unwrap();
        let inode = fs::metadata(&target).unwrap().ino();

        let lock = TargetLock::acquire(&target).unwrap();
        assert!(lock.publish(b"same").unwrap());

        let metadata = fs::metadata(&target).unwrap();
        assert_eq!(metadata.mode() & 0o777, 0o600);
        assert_ne!(metadata.ino(), inode);
    }

    #[test]
    fn missing_parent_and_target_are_created_with_private_modes() {
        let work = tempdir().unwrap();
        let directory = work.path().join("home/.aws");
        let target = directory.join("config");

        let lock = TargetLock::acquire(&target).unwrap();
        lock.publish(b"new").unwrap();

        assert_eq!(fs::metadata(&directory).unwrap().mode() & 0o777, 0o700);
        assert_eq!(fs::metadata(&target).unwrap().mode() & 0o777, 0o600);
    }

    #[test]
    fn target_and_parent_symlinks_are_rejected() {
        let work = tempdir().unwrap();
        let real = work.path().join("real");
        fs::create_dir(&real).unwrap();
        let real_target = real.join("config");
        fs::write(&real_target, b"keep").unwrap();
        let link_target = real.join("link");
        symlink(&real_target, &link_target).unwrap();
        assert!(TargetLock::acquire(&link_target).is_err());
        assert_eq!(fs::read(&real_target).unwrap(), b"keep");

        let parent_link = work.path().join("parent-link");
        symlink(&real, &parent_link).unwrap();
        assert!(TargetLock::acquire(&parent_link.join("config")).is_err());
    }

    #[test]
    fn writable_parent_is_rejected_before_creating_lock_artifacts() {
        let work = tempdir().unwrap();
        let directory = work.path().join("unsafe");
        fs::create_dir(&directory).unwrap();
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o777)).unwrap();

        assert!(TargetLock::acquire(&directory.join("config")).is_err());
        assert!(!directory.join(".aws-config-helper.lock").exists());
    }

    #[test]
    fn failures_before_rename_preserve_the_target_and_clean_up() {
        for stage in [
            PublishStage::Write,
            PublishStage::Sync,
            PublishStage::Rename,
        ] {
            let work = tempdir().unwrap();
            let target = work.path().join("config");
            fs::write(&target, b"old").unwrap();

            let result = atomic_replace_with_hook(&target, work.path(), b"new", |current| {
                if current == stage {
                    Err(io::Error::other("injected failure"))
                } else {
                    Ok(())
                }
            });

            assert!(result.is_err());
            assert!(!result.unwrap_err().is_committed());
            assert_eq!(fs::read(&target).unwrap(), b"old");
            assert!(fs::read_dir(work.path()).unwrap().all(|entry| {
                !entry
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".aws-config-helper.tmp.")
            }));
        }
    }

    #[test]
    fn directory_sync_failure_is_reported_as_committed() {
        let work = tempdir().unwrap();
        let target = work.path().join("config");
        fs::write(&target, b"old").unwrap();

        let error = atomic_replace_with_hook(&target, work.path(), b"new", |current| {
            if current == PublishStage::DirectorySync {
                Err(io::Error::other("injected failure"))
            } else {
                Ok(())
            }
        })
        .unwrap_err();

        assert!(error.is_committed());
        assert_eq!(fs::read(&target).unwrap(), b"new");
    }

    #[test]
    fn oversized_input_is_rejected() {
        let work = tempdir().unwrap();
        let target = work.path().join("config");
        fs::write(&target, vec![b'x'; (MAX_CONFIG_BYTES + 1) as usize]).unwrap();
        assert!(read_required(&target).is_err());
    }

    #[test]
    fn oversized_completed_output_is_rejected_before_publish() {
        let work = tempdir().unwrap();
        let target = work.path().join("config");
        fs::write(&target, b"keep").unwrap();
        let lock = TargetLock::acquire(&target).unwrap();

        assert!(
            lock.publish(&vec![b'x'; (MAX_CONFIG_BYTES + 1) as usize])
                .is_err()
        );
        assert_eq!(fs::read(&target).unwrap(), b"keep");
    }
}
