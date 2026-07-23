use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use crate::error::{AppError, Result};

pub struct TargetLock {
    target: PathBuf,
    directory: PathBuf,
    _lock: File,
}

impl TargetLock {
    pub fn acquire(target: &Path) -> Result<Self> {
        let parent = parent_or_current(target);
        let existed = parent.exists();
        fs::create_dir_all(parent)
            .map_err(|error| AppError::io("create directory", parent, error))?;
        if !existed {
            fs::set_permissions(parent, fs::Permissions::from_mode(0o755))
                .map_err(|error| AppError::io("set directory mode on", parent, error))?;
        }
        let directory = parent
            .canonicalize()
            .map_err(|error| AppError::io("canonicalize", parent, error))?;
        let name = target.file_name().ok_or_else(|| {
            AppError::new(format!(
                "apply-nix-settings: target has no file name: {}",
                target.display()
            ))
        })?;
        let target = directory.join(name);
        validate_target(&target)?;

        let lock_path = directory.join(".apply-nix-settings.lock");
        if let Ok(metadata) = fs::symlink_metadata(&lock_path)
            && !metadata.is_file()
        {
            return Err(AppError::new(format!(
                "apply-nix-settings: lock path is not a regular file: {}",
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

    pub fn replace(&self, content: &[u8]) -> Result<()> {
        atomic_replace_with_hook(&self.target, &self.directory, content, |_| Ok(()))
    }
}

pub(crate) fn parent_or_current(path: &Path) -> &Path {
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
}

pub fn read_target(path: &Path) -> Result<Vec<u8>> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if metadata.file_type().is_symlink() {
                return Err(AppError::new(format!(
                    "apply-nix-settings: target must not be a symlink: {}",
                    path.display()
                )));
            }
            if !metadata.is_file() {
                return Err(AppError::new(format!(
                    "apply-nix-settings: target is not a regular file: {}",
                    path.display()
                )));
            }
            fs::read(path).map_err(|error| AppError::io("read target", path, error))
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(error) => Err(AppError::io("inspect target", path, error)),
    }
}

pub fn read_snippet(path: &Path) -> Result<Vec<u8>> {
    let metadata = fs::metadata(path).map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: snippet not found: {}: {error}",
            path.display()
        ))
    })?;
    if !metadata.is_file() {
        return Err(AppError::new(format!(
            "apply-nix-settings: snippet is not a regular file: {}",
            path.display()
        )));
    }
    fs::read(path).map_err(|error| AppError::io("read snippet", path, error))
}

fn validate_target(path: &Path) -> Result<()> {
    let _ = read_target(path)?;
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AtomicStage {
    Write,
    Sync,
    Rename,
}

fn atomic_replace_with_hook(
    target: &Path,
    directory: &Path,
    content: &[u8],
    mut hook: impl FnMut(AtomicStage) -> io::Result<()>,
) -> Result<()> {
    let mut temporary = tempfile::Builder::new()
        .prefix(".apply-nix-settings.tmp.")
        .tempfile_in(directory)
        .map_err(|error| AppError::io("create temporary file in", directory, error))?;
    temporary
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|error| AppError::io("set temporary mode in", directory, error))?;
    hook(AtomicStage::Write)
        .map_err(|error| AppError::io("write temporary file for", target, error))?;
    temporary
        .write_all(content)
        .map_err(|error| AppError::io("write temporary file for", target, error))?;
    hook(AtomicStage::Sync)
        .map_err(|error| AppError::io("sync temporary file for", target, error))?;
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| AppError::io("sync temporary file for", target, error))?;
    temporary
        .as_file()
        .set_permissions(fs::Permissions::from_mode(0o644))
        .map_err(|error| AppError::io("set target mode for", target, error))?;
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| AppError::io("sync target mode for", target, error))?;
    hook(AtomicStage::Rename)
        .map_err(|error| AppError::io("rename temporary file for", target, error))?;
    temporary
        .persist(target)
        .map_err(|error| AppError::io("rename temporary file for", target, error.error))?;
    sync_directory(directory)?;
    Ok(())
}

fn sync_directory(directory: &Path) -> Result<()> {
    let file = File::open(directory)
        .map_err(|error| AppError::io("open directory for sync", directory, error))?;
    match file.sync_all() {
        Ok(()) => Ok(()),
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::InvalidInput | io::ErrorKind::Unsupported
            ) =>
        {
            Ok(())
        }
        Err(error) => Err(AppError::io("sync directory", directory, error)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{MetadataExt, symlink};
    use std::sync::{Arc, Barrier};
    use std::thread;
    use tempfile::tempdir;

    use crate::managed_block;

    #[test]
    fn a_bare_relative_path_uses_the_current_directory() {
        assert_eq!(
            parent_or_current(Path::new("nix.custom.conf")),
            Path::new(".")
        );
    }

    #[test]
    fn atomically_replaces_content_and_sets_mode() {
        let work = tempdir().unwrap();
        let target = work.path().join("nix.custom.conf");
        fs::write(&target, b"old").unwrap();
        fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).unwrap();
        let lock = TargetLock::acquire(&target).unwrap();
        lock.replace(b"new").unwrap();
        assert_eq!(fs::read(&target).unwrap(), b"new");
        assert_eq!(fs::metadata(&target).unwrap().mode() & 0o777, 0o644);
    }

    #[test]
    fn rejects_target_symlink_and_non_regular_file() {
        let work = tempdir().unwrap();
        let real = work.path().join("real");
        let link = work.path().join("link");
        fs::write(&real, b"keep").unwrap();
        symlink(&real, &link).unwrap();
        assert!(TargetLock::acquire(&link).is_err());
        assert_eq!(fs::read(&real).unwrap(), b"keep");

        let directory = work.path().join("directory");
        fs::create_dir(&directory).unwrap();
        assert!(TargetLock::acquire(&directory).is_err());
    }

    #[test]
    fn injected_failures_preserve_target_and_remove_temporary_files() {
        for stage in [AtomicStage::Write, AtomicStage::Sync, AtomicStage::Rename] {
            let work = tempdir().unwrap();
            let target = work.path().join("nix.custom.conf");
            fs::write(&target, b"old").unwrap();
            fs::set_permissions(&target, fs::Permissions::from_mode(0o600)).unwrap();
            let result = atomic_replace_with_hook(&target, work.path(), b"new", |current| {
                if current == stage {
                    Err(io::Error::other("injected failure"))
                } else {
                    Ok(())
                }
            });
            assert!(result.is_err());
            assert_eq!(fs::read(&target).unwrap(), b"old");
            assert_eq!(fs::metadata(&target).unwrap().mode() & 0o777, 0o600);
            assert!(fs::read_dir(work.path()).unwrap().all(|entry| {
                !entry
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".apply-nix-settings.tmp.")
            }));
        }
    }

    #[test]
    fn a_waiting_writer_reads_the_target_again_after_locking() {
        let work = tempdir().unwrap();
        let target = work.path().join("nix.custom.conf");
        fs::write(&target, b"old").unwrap();
        let lock_path = work.path().join(".apply-nix-settings.lock");
        let holder = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)
            .unwrap();
        holder.lock().unwrap();

        let waiting_target = target.clone();
        let waiting = thread::spawn(move || {
            let lock = TargetLock::acquire(&waiting_target).unwrap();
            read_target(lock.target()).unwrap()
        });
        thread::yield_now();
        fs::write(&target, b"new").unwrap();
        holder.unlock().unwrap();

        assert_eq!(waiting.join().unwrap(), b"new");
    }

    #[test]
    fn concurrent_updates_never_mix_managed_blocks() {
        let work = tempdir().unwrap();
        let target = work.path().join("nix.custom.conf");
        fs::write(&target, b"before = keep\n").unwrap();
        let barrier = Arc::new(Barrier::new(3));
        let mut writers = Vec::new();
        for snippet in [b"writer = one\n".as_slice(), b"writer = two\n"] {
            let target = target.clone();
            let barrier = Arc::clone(&barrier);
            let snippet = snippet.to_vec();
            writers.push(thread::spawn(move || {
                barrier.wait();
                let lock = TargetLock::acquire(&target).unwrap();
                let current = read_target(lock.target()).unwrap();
                let desired = managed_block::render_desired(&current, &snippet).unwrap();
                lock.replace(&desired).unwrap();
            }));
        }
        barrier.wait();
        for writer in writers {
            writer.join().unwrap();
        }

        let content = fs::read(&target).unwrap();
        assert_eq!(
            content
                .windows(managed_block::BEGIN_MARKER.len())
                .filter(|window| *window == managed_block::BEGIN_MARKER)
                .count(),
            1
        );
        assert!(
            content
                .windows(b"writer = one".len())
                .any(|window| window == b"writer = one")
                || content
                    .windows(b"writer = two".len())
                    .any(|window| window == b"writer = two")
        );
    }
}
