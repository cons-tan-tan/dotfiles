use std::fs::{self, DirBuilder, File, Permissions};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::path::Path;

use tempfile::NamedTempFile;

use crate::error::AppError;
use crate::manifest::{Entry, validate_destination};

pub fn place(entry: &Entry, home: &Path, content: &[u8]) -> Result<(), AppError> {
    validate_destination(home, Path::new(&entry.relative_destination), 1)?;
    let parent = entry.destination.parent().ok_or_else(|| {
        AppError::Manifest(format!(
            "dst '{}' has no parent directory",
            entry.relative_destination
        ))
    })?;
    create_directories(
        home,
        Path::new(&entry.relative_destination),
        entry.directory_mode,
    )?;
    // Recheck immediately before placement. Atomic rename never follows a
    // final-component symlink. Replacing a checked parent concurrently would
    // require directory-fd APIs; same-UID path mutation is outside this
    // command's threat model.
    validate_destination(home, Path::new(&entry.relative_destination), 1)?;

    write_atomic(parent, &entry.destination, content, entry.mode)
}

fn write_atomic(
    parent: &Path,
    destination: &Path,
    content: &[u8],
    mode: u32,
) -> Result<(), AppError> {
    let mut temporary = NamedTempFile::new_in(parent)
        .map_err(|error| AppError::io("failed to create temporary file in", parent, error))?;
    temporary
        .as_file_mut()
        .write_all(content)
        .map_err(|error| AppError::io("failed to write temporary file for", destination, error))?;
    temporary
        .as_file()
        .set_permissions(Permissions::from_mode(mode))
        .map_err(|error| {
            AppError::io(
                "failed to set temporary file permissions for",
                destination,
                error,
            )
        })?;
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| AppError::io("failed to sync temporary file for", destination, error))?;
    temporary
        .persist(destination)
        .map_err(|error| AppError::io("failed to replace destination", destination, error.error))?;

    if let Ok(directory) = File::open(parent) {
        let _ = directory.sync_all();
    }
    Ok(())
}

fn create_directories(
    home: &Path,
    relative_destination: &Path,
    directory_mode: u32,
) -> Result<(), AppError> {
    let relative_parent = relative_destination.parent().ok_or_else(|| {
        AppError::Manifest(format!(
            "dst '{}' has no parent directory",
            relative_destination.display()
        ))
    })?;
    let mut current = home.to_path_buf();
    for component in relative_parent.components() {
        current.push(component.as_os_str());
        match fs::symlink_metadata(&current) {
            Ok(metadata) => {
                if metadata.file_type().is_symlink() || !metadata.is_dir() {
                    return Err(AppError::Manifest(format!(
                        "dst '{}' has an unsafe parent",
                        relative_destination.display()
                    )));
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                let mut builder = DirBuilder::new();
                builder.mode(0o700);
                match builder.create(&current) {
                    Ok(()) => {
                        // DirBuilder's mode is filtered by the caller's umask.
                        // Secure each new component before descending into it.
                        fs::set_permissions(&current, Permissions::from_mode(0o700)).map_err(
                            |error| {
                                AppError::io(
                                    "failed to secure destination directory",
                                    &current,
                                    error,
                                )
                            },
                        )?;
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                        let metadata = fs::symlink_metadata(&current).map_err(|error| {
                            AppError::io("failed to inspect destination directory", &current, error)
                        })?;
                        if metadata.file_type().is_symlink() || !metadata.is_dir() {
                            return Err(AppError::Manifest(format!(
                                "dst '{}' has an unsafe parent",
                                relative_destination.display()
                            )));
                        }
                    }
                    Err(error) => {
                        return Err(AppError::io(
                            "failed to create destination directory",
                            &current,
                            error,
                        ));
                    }
                }
            }
            Err(error) => {
                return Err(AppError::io(
                    "failed to inspect destination directory",
                    &current,
                    error,
                ));
            }
        }
    }

    let direct_parent = home.join(relative_parent);
    fs::set_permissions(&direct_parent, Permissions::from_mode(directory_mode)).map_err(|error| {
        AppError::io(
            "failed to set destination directory permissions for",
            direct_parent,
            error,
        )
    })
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::{MetadataExt, symlink};

    use tempfile::TempDir;

    use super::*;
    use crate::manifest::Format;

    fn entry(home: &Path) -> Entry {
        Entry {
            relative_source: "secrets/source".to_owned(),
            relative_destination: "nested/private".to_owned(),
            source: home.join("unused"),
            destination: home.join("nested/private"),
            format: Format::Raw,
            mode: 0o600,
            directory_mode: 0o700,
        }
    }

    #[test]
    fn writes_atomically_with_requested_permissions() {
        let temp = TempDir::new().unwrap();
        let home = temp.path();
        let entry = entry(home);
        place(&entry, home, b"secret").unwrap();
        assert_eq!(fs::read(&entry.destination).unwrap(), b"secret");
        assert_eq!(
            fs::metadata(&entry.destination).unwrap().mode() & 0o777,
            0o600
        );
        assert_eq!(
            fs::metadata(entry.destination.parent().unwrap())
                .unwrap()
                .mode()
                & 0o777,
            0o700
        );
    }

    #[test]
    fn rejects_destination_symlink_without_touching_target() {
        let temp = TempDir::new().unwrap();
        let home = temp.path();
        fs::create_dir(home.join("nested")).unwrap();
        let outside = home.join("outside");
        fs::write(&outside, b"keep").unwrap();
        symlink(&outside, home.join("nested/private")).unwrap();
        let entry = entry(home);
        assert!(place(&entry, home, b"secret").is_err());
        assert_eq!(fs::read(outside).unwrap(), b"keep");
    }

    #[test]
    fn removes_temporary_file_when_persist_fails() {
        let temp = TempDir::new().unwrap();
        let destination = temp.path().join("existing-directory");
        fs::create_dir(&destination).unwrap();

        assert!(write_atomic(temp.path(), &destination, b"secret", 0o600).is_err());
        let entries = fs::read_dir(temp.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect::<Vec<_>>();
        assert_eq!(entries, vec![destination.file_name().unwrap()]);
    }
}
