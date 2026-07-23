use std::collections::{BTreeMap, BTreeSet};
use std::fs::{File, OpenOptions, Permissions};
use std::io::Write as _;
use std::path::{Component, Path, PathBuf};

use fs2::FileExt as _;
use tempfile::Builder;

use crate::command::{CommandRunner, CommandSpec, require_success, run_checked};
use crate::error::UpdateError;

const GLOBAL_MANAGED_PATHS: [&str; 5] = [
    ":(glob)nix/pins/*.json",
    "flake.nix",
    "flake.lock",
    "nix/packages/shellfirm/Cargo.lock",
    "nix/packages/difit/package-lock.json",
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Repository {
    root: PathBuf,
    git_dir: PathBuf,
}

impl Repository {
    pub fn discover<R: CommandRunner>(runner: &R) -> Result<Self, UpdateError> {
        Self::discover_from(runner, None)
    }

    pub fn discover_in<R: CommandRunner>(
        runner: &R,
        directory: impl AsRef<Path>,
    ) -> Result<Self, UpdateError> {
        Self::discover_from(runner, Some(directory.as_ref()))
    }

    fn discover_from<R: CommandRunner>(
        runner: &R,
        directory: Option<&Path>,
    ) -> Result<Self, UpdateError> {
        let mut root_command = CommandSpec::new("git").args(["rev-parse", "--show-toplevel"]);
        if let Some(directory) = directory {
            root_command = root_command.current_dir(directory);
        }
        let root_output = run_checked(runner, &root_command)?;
        let root = parse_path_output(&root_command, &root_output.stdout)?;

        let git_dir_command = CommandSpec::new("git")
            .args(["rev-parse", "--absolute-git-dir"])
            .current_dir(&root);
        let git_dir_output = run_checked(runner, &git_dir_command)?;
        let git_dir = parse_path_output(&git_dir_command, &git_dir_output.stdout)?;

        Ok(Self { root, git_dir })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn git_dir(&self) -> &Path {
        &self.git_dir
    }
}

#[derive(Debug)]
enum FileSnapshot {
    Present {
        bytes: Vec<u8>,
        permissions: Permissions,
    },
    Absent,
}

pub struct Transaction<'a, R: CommandRunner> {
    repository: Repository,
    runner: &'a R,
    _lock: File,
    snapshots: BTreeMap<PathBuf, FileSnapshot>,
    managed_paths: Option<BTreeSet<PathBuf>>,
    state: FinalizationState,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FinalizationState {
    Active,
    Committed,
    RolledBack,
    Failed,
}

impl<'a, R: CommandRunner> Transaction<'a, R> {
    pub fn begin(repository: Repository, runner: &'a R) -> Result<Self, UpdateError> {
        Self::begin_inner(repository, runner, None)
    }

    pub fn begin_scoped<I, P>(
        repository: Repository,
        runner: &'a R,
        managed_paths: I,
    ) -> Result<Self, UpdateError>
    where
        I: IntoIterator<Item = P>,
        P: AsRef<Path>,
    {
        let managed_paths = managed_paths
            .into_iter()
            .map(|path| path.as_ref().to_owned())
            .collect::<BTreeSet<_>>();
        if managed_paths.is_empty() {
            return Err(UpdateError::message(
                "update-pins: target scope did not declare any managed paths",
            ));
        }
        for path in &managed_paths {
            validate_relative_path(path)?;
        }
        Self::begin_inner(repository, runner, Some(managed_paths))
    }

    fn begin_inner(
        repository: Repository,
        runner: &'a R,
        managed_paths: Option<BTreeSet<PathBuf>>,
    ) -> Result<Self, UpdateError> {
        let lock_path = repository.git_dir.join("update-pins.lock");
        let lock = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .open(&lock_path)
            .map_err(|source| UpdateError::io(&lock_path, source))?;
        lock.try_lock_exclusive().map_err(|source| {
            if source.kind() == std::io::ErrorKind::WouldBlock {
                UpdateError::AlreadyRunning
            } else {
                UpdateError::io(&lock_path, source)
            }
        })?;

        let global_pathspecs = GLOBAL_MANAGED_PATHS.map(PathBuf::from);
        let pathspecs = managed_paths
            .as_ref()
            .map(|paths| paths.iter().cloned().collect::<Vec<_>>())
            .unwrap_or_else(|| global_pathspecs.to_vec());
        check_managed_files_clean(&repository.root, runner, &pathspecs)?;
        let managed = match &managed_paths {
            Some(paths) => paths.clone(),
            None => load_managed_files(&repository.root, runner, &pathspecs)?,
        };
        let mut snapshots = BTreeMap::new();
        for relative in managed {
            if managed_paths.is_some() {
                validate_relative_path(&relative)?;
            } else {
                ensure_managed_path(&relative)?;
            }
            ensure_safe_repository_path(&repository.root, &relative)?;
            let path = repository.root.join(&relative);
            let snapshot = match std::fs::read(&path) {
                Ok(bytes) => {
                    let permissions = std::fs::metadata(&path)
                        .map_err(|source| UpdateError::io(&path, source))?
                        .permissions();
                    FileSnapshot::Present { bytes, permissions }
                }
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => FileSnapshot::Absent,
                Err(error) => return Err(UpdateError::io(&path, error)),
            };
            snapshots.insert(relative, snapshot);
        }

        Ok(Self {
            repository,
            runner,
            _lock: lock,
            snapshots,
            managed_paths,
            state: FinalizationState::Active,
        })
    }

    pub fn root(&self) -> &Path {
        &self.repository.root
    }

    pub fn runner(&self) -> &R {
        self.runner
    }

    pub fn read(&self, relative: impl AsRef<Path>) -> Result<Vec<u8>, UpdateError> {
        let relative = relative.as_ref();
        self.ensure_authorized_path(relative)?;
        ensure_safe_repository_path(&self.repository.root, relative)?;
        let path = self.repository.root.join(relative);
        std::fs::read(&path).map_err(|source| UpdateError::io(path, source))
    }

    pub fn replace(
        &mut self,
        relative: impl AsRef<Path>,
        contents: &[u8],
    ) -> Result<bool, UpdateError> {
        self.write_if_changed(relative, contents)
    }

    pub fn write_if_changed(
        &mut self,
        relative: impl AsRef<Path>,
        contents: &[u8],
    ) -> Result<bool, UpdateError> {
        self.ensure_active()?;
        let relative = relative.as_ref();
        self.ensure_authorized_path(relative)?;
        ensure_safe_repository_path(&self.repository.root, relative)?;
        let path = self.repository.root.join(relative);
        let current = match std::fs::read(&path) {
            Ok(bytes) => Some(bytes),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(error) => return Err(UpdateError::io(&path, error)),
        };
        if current.as_deref() == Some(contents) {
            return Ok(false);
        }
        self.snapshot_if_needed(relative)?;
        let permissions = std::fs::metadata(&path)
            .map(|metadata| Some(metadata.permissions()))
            .or_else(|error| {
                if error.kind() == std::io::ErrorKind::NotFound {
                    Ok(None)
                } else {
                    Err(UpdateError::io(&path, error))
                }
            })?;
        atomic_replace(&path, contents, permissions)?;
        Ok(true)
    }

    pub fn remove(&mut self, relative: impl AsRef<Path>) -> Result<bool, UpdateError> {
        self.ensure_active()?;
        let relative = relative.as_ref();
        self.ensure_authorized_path(relative)?;
        self.snapshot_if_needed(relative)?;
        let path = self.repository.root.join(relative);
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(error) => Err(UpdateError::io(path, error)),
        }
    }

    pub fn rollback(&mut self) -> Result<(), UpdateError> {
        self.rollback_with_unlock(fs2::FileExt::unlock)
    }

    fn rollback_with_unlock(
        &mut self,
        unlock: impl FnOnce(&File) -> std::io::Result<()>,
    ) -> Result<(), UpdateError> {
        if self.state != FinalizationState::Active {
            return Err(UpdateError::TransactionFinalized);
        }
        let restore = self.rollback_inner();
        let unlock = unlock(&self._lock).map_err(|source| {
            UpdateError::io(self.repository.git_dir.join("update-pins.lock"), source)
        });
        self.state = if restore.is_ok() && unlock.is_ok() {
            FinalizationState::RolledBack
        } else {
            FinalizationState::Failed
        };
        match (restore, unlock) {
            (Ok(()), Ok(())) => Ok(()),
            (Err(restore), Ok(())) => Err(restore),
            (Ok(()), Err(unlock)) => Err(UpdateError::RollbackUnlock {
                unlock: Box::new(unlock),
            }),
            (Err(restore), Err(unlock)) => Err(UpdateError::RollbackAndUnlock {
                restore: Box::new(restore),
                unlock: Box::new(unlock),
            }),
        }
    }

    fn rollback_inner(&mut self) -> Result<(), UpdateError> {
        if self.state != FinalizationState::Active {
            return Ok(());
        }

        let mut failures = Vec::new();
        for (relative, snapshot) in self.snapshots.iter().rev() {
            let path = self.repository.root.join(relative);
            if let Err(error) = ensure_safe_repository_path(&self.repository.root, relative) {
                failures.push(format!("{}: {error}", path.display()));
                continue;
            }
            match snapshot {
                FileSnapshot::Present { bytes, permissions } => {
                    let current = std::fs::read(&path);
                    let current_mode =
                        std::fs::metadata(&path).map(|metadata| metadata.permissions());
                    let already_restored = current.as_ref().is_ok_and(|current| current == bytes)
                        && current_mode
                            .as_ref()
                            .is_ok_and(|current| same_permissions(current, permissions));
                    if already_restored {
                        continue;
                    }
                    if let Err(error) = atomic_replace(&path, bytes, Some(permissions.clone())) {
                        failures.push(format!("{}: {error}", path.display()));
                    }
                }
                FileSnapshot::Absent => {
                    if let Err(error) = std::fs::remove_file(&path)
                        && error.kind() != std::io::ErrorKind::NotFound
                    {
                        failures.push(format!("{}: {error}", path.display()));
                    }
                }
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(UpdateError::Rollback(failures.join("; ")))
        }
    }

    pub fn commit(&mut self) -> Result<(), UpdateError> {
        self.commit_with_unlock(fs2::FileExt::unlock)
    }

    fn commit_with_unlock(
        &mut self,
        unlock: impl FnOnce(&File) -> std::io::Result<()>,
    ) -> Result<(), UpdateError> {
        self.ensure_active()?;
        self.preserve_snapshot_permissions()?;
        unlock(&self._lock)
            .map_err(|source| {
                UpdateError::io(self.repository.git_dir.join("update-pins.lock"), source)
            })
            .map(|()| {
                self.state = FinalizationState::Committed;
            })
    }

    fn preserve_snapshot_permissions(&self) -> Result<(), UpdateError> {
        for (relative, snapshot) in &self.snapshots {
            let FileSnapshot::Present { permissions, .. } = snapshot else {
                continue;
            };
            ensure_safe_repository_path(&self.repository.root, relative)?;
            let path = self.repository.root.join(relative);
            let current = std::fs::metadata(&path)
                .map_err(|source| UpdateError::io(&path, source))?
                .permissions();
            if !same_permissions(&current, permissions) {
                std::fs::set_permissions(&path, permissions.clone())
                    .map_err(|source| UpdateError::io(&path, source))?;
            }
        }
        Ok(())
    }

    fn unlock(&self) -> Result<(), UpdateError> {
        fs2::FileExt::unlock(&self._lock).map_err(|source| {
            UpdateError::io(self.repository.git_dir.join("update-pins.lock"), source)
        })
    }

    fn snapshot_if_needed(&mut self, relative: &Path) -> Result<(), UpdateError> {
        self.ensure_active()?;
        self.ensure_authorized_path(relative)?;
        ensure_safe_repository_path(&self.repository.root, relative)?;
        if self.snapshots.contains_key(relative) {
            return Ok(());
        }

        let path = self.repository.root.join(relative);
        let snapshot = match std::fs::read(&path) {
            Ok(bytes) => {
                let permissions = std::fs::metadata(&path)
                    .map_err(|source| UpdateError::io(&path, source))?
                    .permissions();
                FileSnapshot::Present { bytes, permissions }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => FileSnapshot::Absent,
            Err(error) => return Err(UpdateError::io(&path, error)),
        };
        self.snapshots.insert(relative.to_owned(), snapshot);
        Ok(())
    }

    fn ensure_authorized_path(&self, path: &Path) -> Result<(), UpdateError> {
        match &self.managed_paths {
            Some(managed) => {
                validate_relative_path(path)?;
                if !managed.contains(path) {
                    return Err(UpdateError::UnmanagedPath(path.to_owned()));
                }
            }
            None => ensure_managed_path(path)?,
        }
        Ok(())
    }

    fn ensure_active(&self) -> Result<(), UpdateError> {
        if self.state == FinalizationState::Active {
            Ok(())
        } else {
            Err(UpdateError::TransactionFinalized)
        }
    }
}

impl<R: CommandRunner> Drop for Transaction<'_, R> {
    fn drop(&mut self) {
        if self.state == FinalizationState::Active {
            let _ = self.rollback_inner();
            let _ = self.unlock();
            self.state = FinalizationState::RolledBack;
        }
    }
}

fn check_managed_files_clean<R: CommandRunner>(
    root: &Path,
    runner: &R,
    pathspecs: &[PathBuf],
) -> Result<(), UpdateError> {
    let unstaged = CommandSpec::new("git")
        .arg("diff")
        .arg("--quiet")
        .arg("--")
        .args(pathspecs.iter().map(|path| path.as_os_str()))
        .current_dir(root);
    let output = runner.run(&unstaged)?;
    match output.status {
        Some(0) => {}
        Some(1) => return Err(UpdateError::DirtyManagedFiles { kind: "unstaged" }),
        _ => {
            require_success(&unstaged, output)?;
        }
    }

    let staged = CommandSpec::new("git")
        .arg("diff")
        .arg("--cached")
        .arg("--quiet")
        .arg("--")
        .args(pathspecs.iter().map(|path| path.as_os_str()))
        .current_dir(root);
    let output = runner.run(&staged)?;
    match output.status {
        Some(0) => {}
        Some(1) => return Err(UpdateError::DirtyManagedFiles { kind: "staged" }),
        _ => {
            require_success(&staged, output)?;
        }
    }
    Ok(())
}

fn load_managed_files<R: CommandRunner>(
    root: &Path,
    runner: &R,
    pathspecs: &[PathBuf],
) -> Result<BTreeSet<PathBuf>, UpdateError> {
    let tracked = CommandSpec::new("git")
        .arg("ls-files")
        .arg("-z")
        .arg("--")
        .args(pathspecs.iter().map(|path| path.as_os_str()))
        .current_dir(root);
    let untracked = CommandSpec::new("git")
        .arg("ls-files")
        .arg("-z")
        .arg("--others")
        .arg("--exclude-standard")
        .arg("--")
        .args(pathspecs.iter().map(|path| path.as_os_str()))
        .current_dir(root);

    let mut files = BTreeSet::new();
    for command in [&tracked, &untracked] {
        let output = run_checked(runner, command)?;
        for path in output.stdout.split(|byte| *byte == b'\0') {
            if path.is_empty() {
                continue;
            }
            let path = std::str::from_utf8(path)
                .map_err(|_| UpdateError::NonUtf8Output {
                    command: command.display(),
                })?
                .into();
            files.insert(path);
        }
    }
    Ok(files)
}

fn validate_relative_path(path: &Path) -> Result<(), UpdateError> {
    if path.as_os_str().is_empty()
        || path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(UpdateError::UnsafeManagedPath(path.to_owned()));
    }
    Ok(())
}

fn ensure_managed_path(path: &Path) -> Result<(), UpdateError> {
    validate_relative_path(path)?;
    let is_pin = path.parent() == Some(Path::new("nix/pins"))
        && path
            .extension()
            .is_some_and(|extension| extension == "json");
    let is_fixed = [
        Path::new("flake.nix"),
        Path::new("flake.lock"),
        Path::new("nix/packages/difit/package-lock.json"),
    ]
    .contains(&path);
    if is_pin || is_fixed {
        Ok(())
    } else {
        Err(UpdateError::UnmanagedPath(path.to_owned()))
    }
}

fn ensure_safe_repository_path(root: &Path, relative: &Path) -> Result<(), UpdateError> {
    validate_relative_path(relative)?;
    let canonical_root =
        std::fs::canonicalize(root).map_err(|source| UpdateError::io(root, source))?;
    let target = root.join(relative);
    let parent = target
        .parent()
        .ok_or_else(|| UpdateError::UnsafeManagedPath(relative.to_owned()))?;
    let canonical_parent =
        std::fs::canonicalize(parent).map_err(|source| UpdateError::io(parent, source))?;
    if !canonical_parent.starts_with(&canonical_root) {
        return Err(UpdateError::UnsafeManagedPath(relative.to_owned()));
    }

    let mut current = root.to_owned();
    if let Some(parent_relative) = relative.parent() {
        for component in parent_relative.components() {
            current.push(component);
            let metadata = std::fs::symlink_metadata(&current)
                .map_err(|source| UpdateError::io(&current, source))?;
            if metadata.file_type().is_symlink() || !metadata.is_dir() {
                return Err(UpdateError::UnsafeManagedPath(relative.to_owned()));
            }
        }
    }

    match std::fs::symlink_metadata(&target) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            Err(UpdateError::UnsafeManagedPath(relative.to_owned()))
        }
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(UpdateError::io(target, error)),
    }
}

fn atomic_replace(
    path: &Path,
    contents: &[u8],
    permissions: Option<Permissions>,
) -> Result<(), UpdateError> {
    let parent = path
        .parent()
        .ok_or_else(|| UpdateError::UnsafeManagedPath(path.to_owned()))?;
    let base = path
        .file_name()
        .ok_or_else(|| UpdateError::UnsafeManagedPath(path.to_owned()))?
        .to_string_lossy();
    let mut temporary = Builder::new()
        .prefix(&format!(".{base}.update-pins."))
        .tempfile_in(parent)
        .map_err(|source| UpdateError::io(parent, source))?;
    temporary
        .write_all(contents)
        .map_err(|source| UpdateError::io(temporary.path(), source))?;
    if let Some(permissions) = permissions {
        temporary
            .as_file_mut()
            .set_permissions(permissions)
            .map_err(|source| UpdateError::io(temporary.path(), source))?;
    }
    temporary
        .as_file_mut()
        .sync_all()
        .map_err(|source| UpdateError::io(temporary.path(), source))?;
    temporary
        .persist(path)
        .map_err(|error| UpdateError::io(path, error.error))?;
    Ok(())
}

#[cfg(unix)]
fn same_permissions(left: &Permissions, right: &Permissions) -> bool {
    use std::os::unix::fs::PermissionsExt as _;

    left.mode() == right.mode()
}

#[cfg(not(unix))]
fn same_permissions(left: &Permissions, right: &Permissions) -> bool {
    left.readonly() == right.readonly()
}

fn parse_path_output(command: &CommandSpec, output: &[u8]) -> Result<PathBuf, UpdateError> {
    let value = std::str::from_utf8(output)
        .map_err(|_| UpdateError::NonUtf8Output {
            command: command.display(),
        })?
        .trim();
    if value.is_empty() {
        return Err(UpdateError::NonUtf8Output {
            command: command.display(),
        });
    }
    Ok(value.into())
}

#[cfg(test)]
mod tests {
    use std::fs::Permissions;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    use tempfile::TempDir;

    use super::{Repository, Transaction, check_managed_files_clean};
    use crate::command::{CommandOutput, CommandRunner, CommandSpec, SystemCommandRunner};
    use crate::error::UpdateError;

    struct TestRepository {
        directory: TempDir,
    }

    struct FailingDiffRunner;

    impl CommandRunner for FailingDiffRunner {
        fn run(&self, _command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            Ok(CommandOutput {
                status: Some(128),
                stdout: Vec::new(),
                stderr: b"fatal: repository unavailable".to_vec(),
            })
        }

        fn is_available(&self, _program: &Path) -> bool {
            false
        }
    }

    impl TestRepository {
        fn new() -> Self {
            let directory = tempfile::tempdir().expect("temporary repository");
            run_git(directory.path(), ["init", "-q"]);
            run_git(
                directory.path(),
                ["config", "user.email", "test@example.invalid"],
            );
            run_git(
                directory.path(),
                ["config", "user.name", "update-pins test"],
            );
            std::fs::create_dir_all(directory.path().join("nix/pins")).expect("pin directory");
            std::fs::write(
                directory.path().join("nix/pins/example.json"),
                b"{\"hash\":\"old\"}\n",
            )
            .expect("pin");
            std::fs::write(directory.path().join("flake.nix"), b"{}\n").expect("flake");
            std::fs::write(directory.path().join("flake.lock"), b"{}\n").expect("lock");
            run_git(directory.path(), ["add", "."]);
            run_git(directory.path(), ["commit", "-q", "-m", "initial"]);
            Self { directory }
        }

        fn path(&self) -> &Path {
            self.directory.path()
        }

        fn repository(&self) -> Repository {
            Repository {
                root: self.path().to_owned(),
                git_dir: self.path().join(".git"),
            }
        }
    }

    #[test]
    fn replace_preserves_mode_and_rollback_restores_bytes() {
        use std::os::unix::fs::PermissionsExt as _;

        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        std::fs::set_permissions(&pin, Permissions::from_mode(0o440)).expect("restrict pin");

        {
            let runner = SystemCommandRunner;
            let mut transaction =
                Transaction::begin(repository.repository(), &runner).expect("begin transaction");
            assert!(
                transaction
                    .replace("nix/pins/example.json", b"{\"hash\":\"new\"}\n")
                    .expect("replace pin")
            );
            assert_eq!(
                std::fs::metadata(&pin)
                    .expect("pin metadata")
                    .permissions()
                    .mode()
                    & 0o777,
                0o440
            );
        }

        assert_eq!(
            std::fs::read(&pin).expect("restored pin"),
            b"{\"hash\":\"old\"}\n"
        );
        assert_eq!(
            std::fs::metadata(&pin)
                .expect("pin metadata")
                .permissions()
                .mode()
                & 0o777,
            0o440
        );
        assert_no_staging_files(repository.path());
    }

    #[test]
    fn replace_preserves_special_permission_bits() {
        use std::os::unix::fs::PermissionsExt as _;

        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        std::fs::set_permissions(&pin, Permissions::from_mode(0o750)).expect("make pin executable");
        run_git(repository.path(), ["add", "nix/pins/example.json"]);
        run_git(
            repository.path(),
            ["commit", "-q", "-m", "make fixture executable"],
        );
        if let Err(error) = std::fs::set_permissions(&pin, Permissions::from_mode(0o4750)) {
            assert_eq!(
                error.kind(),
                std::io::ErrorKind::PermissionDenied,
                "unexpected error setting special permission bits"
            );
            return;
        }

        let runner = SystemCommandRunner;
        let mut transaction =
            Transaction::begin(repository.repository(), &runner).expect("begin transaction");
        transaction
            .replace("nix/pins/example.json", b"{\"hash\":\"new\"}\n")
            .expect("replace pin");

        assert_eq!(
            std::fs::metadata(&pin)
                .expect("pin metadata")
                .permissions()
                .mode()
                & 0o7777,
            0o4750
        );
    }

    #[cfg(unix)]
    #[test]
    fn identical_write_does_not_replace_or_touch_the_file() {
        use std::os::unix::fs::MetadataExt as _;

        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        let runner = SystemCommandRunner;
        let mut transaction =
            Transaction::begin(repository.repository(), &runner).expect("begin transaction");
        let before = std::fs::metadata(&pin).expect("metadata before identical write");
        let snapshot_count = transaction.snapshots.len();

        assert!(
            !transaction
                .write_if_changed("nix/pins/example.json", b"{\"hash\":\"old\"}\n")
                .expect("identical write")
        );

        let after = std::fs::metadata(&pin).expect("metadata after identical write");
        assert_eq!(after.ino(), before.ino());
        assert_eq!(after.mode(), before.mode());
        assert_eq!(after.mtime(), before.mtime());
        assert_eq!(after.mtime_nsec(), before.mtime_nsec());
        assert_eq!(transaction.snapshots.len(), snapshot_count);
    }

    #[test]
    fn commit_keeps_replacement_and_releases_lock() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let repo = repository.repository();
        let mut transaction = Transaction::begin(repo.clone(), &runner).expect("begin transaction");
        transaction
            .replace("nix/pins/example.json", b"{\"hash\":\"new\"}\n")
            .expect("replace pin");
        transaction.commit().expect("commit transaction");

        run_git(repository.path(), ["add", "nix/pins/example.json"]);
        run_git(repository.path(), ["commit", "-q", "-m", "updated"]);
        Transaction::begin(repo, &runner).expect("lock should be released");
    }

    #[cfg(unix)]
    #[test]
    fn commit_restores_mode_after_an_external_atomic_replacement() {
        use std::os::unix::fs::PermissionsExt as _;

        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        std::fs::set_permissions(&pin, Permissions::from_mode(0o440)).expect("restrict pin");
        let runner = SystemCommandRunner;
        let mut transaction =
            Transaction::begin(repository.repository(), &runner).expect("begin transaction");

        std::fs::remove_file(&pin).expect("remove pin like an external atomic updater");
        std::fs::write(&pin, b"{\"hash\":\"external\"}\n").expect("replace pin externally");
        std::fs::set_permissions(&pin, Permissions::from_mode(0o644))
            .expect("external updater mode");
        transaction.commit().expect("commit transaction");

        assert_eq!(
            std::fs::metadata(&pin)
                .expect("pin metadata")
                .permissions()
                .mode()
                & 0o777,
            0o440
        );
        assert_eq!(
            std::fs::read(pin).expect("committed external replacement"),
            b"{\"hash\":\"external\"}\n"
        );
    }

    #[test]
    fn failed_commit_remains_active_for_explicit_rollback() {
        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        let runner = SystemCommandRunner;
        let mut transaction =
            Transaction::begin(repository.repository(), &runner).expect("begin transaction");
        transaction
            .write_if_changed("nix/pins/example.json", b"{\"hash\":\"new\"}\n")
            .expect("replace pin");

        let error = transaction
            .commit_with_unlock(|_| Err(std::io::Error::other("injected unlock failure")))
            .expect_err("commit should fail");

        assert!(error.to_string().contains("injected unlock failure"));
        assert_eq!(transaction.state, super::FinalizationState::Active);
        transaction
            .rollback()
            .expect("failed commit can be rolled back explicitly");
        assert_eq!(
            std::fs::read(pin).expect("restored pin"),
            b"{\"hash\":\"old\"}\n"
        );
        assert_eq!(transaction.state, super::FinalizationState::RolledBack);
    }

    #[test]
    fn rollback_preserves_restore_and_unlock_failures() {
        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        let runner = SystemCommandRunner;
        let mut transaction =
            Transaction::begin(repository.repository(), &runner).expect("begin transaction");
        transaction
            .write_if_changed("nix/pins/example.json", b"{\"hash\":\"new\"}\n")
            .expect("replace pin");
        std::fs::remove_file(&pin).expect("remove candidate file");
        std::fs::create_dir(&pin).expect("block restoration with a directory");

        let error = transaction
            .rollback_with_unlock(|_| Err(std::io::Error::other("injected unlock failure")))
            .expect_err("rollback should retain both failures");

        assert!(matches!(
            error,
            UpdateError::RollbackAndUnlock { restore, unlock }
                if restore.to_string().contains("rollback failed")
                    && unlock.to_string().contains("injected unlock failure")
        ));
        assert_eq!(transaction.state, super::FinalizationState::Failed);
        assert!(matches!(
            transaction.commit(),
            Err(UpdateError::TransactionFinalized)
        ));
    }

    #[test]
    fn finalized_transactions_reject_writes_and_repeated_finalization() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let mut transaction =
            Transaction::begin(repository.repository(), &runner).expect("begin transaction");
        transaction.commit().expect("commit transaction");

        assert!(matches!(
            transaction.write_if_changed("nix/pins/example.json", b"changed\n"),
            Err(UpdateError::TransactionFinalized)
        ));
        assert!(matches!(
            transaction.remove("nix/pins/example.json"),
            Err(UpdateError::TransactionFinalized)
        ));
        assert!(matches!(
            transaction.commit(),
            Err(UpdateError::TransactionFinalized)
        ));
        assert!(matches!(
            transaction.rollback(),
            Err(UpdateError::TransactionFinalized)
        ));
    }

    #[test]
    fn rollback_removes_created_files_and_restores_deleted_files() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let existing = repository.path().join("nix/pins/example.json");
        let created = repository.path().join("nix/pins/created.json");

        {
            let mut transaction =
                Transaction::begin(repository.repository(), &runner).expect("begin transaction");
            transaction
                .replace("nix/pins/created.json", b"{\"hash\":\"created\"}\n")
                .expect("create pin");
            transaction
                .remove("nix/pins/example.json")
                .expect("delete pin");
            assert!(created.is_file());
            assert!(!existing.exists());
        }

        assert!(!created.exists());
        assert_eq!(
            std::fs::read(existing).expect("restored deleted pin"),
            b"{\"hash\":\"old\"}\n"
        );
        assert_no_staging_files(repository.path());
    }

    #[test]
    fn explicit_rollback_restores_files_and_releases_lock() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let repo = repository.repository();
        let mut transaction = Transaction::begin(repo.clone(), &runner).expect("begin transaction");
        transaction
            .replace("nix/pins/example.json", b"{\"hash\":\"new\"}\n")
            .expect("replace pin");

        transaction.rollback().expect("explicit rollback");

        assert_eq!(
            std::fs::read(repository.path().join("nix/pins/example.json")).expect("restored pin"),
            b"{\"hash\":\"old\"}\n"
        );
        Transaction::begin(repo, &runner).expect("rollback should release lock");
    }

    #[test]
    fn dirty_managed_files_are_rejected() {
        let repository = TestRepository::new();
        std::fs::write(
            repository.path().join("nix/pins/example.json"),
            b"{\"dirty\":true}\n",
        )
        .expect("dirty pin");
        let runner = SystemCommandRunner;

        let error = Transaction::begin(repository.repository(), &runner)
            .err()
            .expect("dirty transaction should fail");

        assert!(matches!(
            error,
            UpdateError::DirtyManagedFiles { kind: "unstaged" }
        ));
    }

    #[test]
    fn scoped_transaction_ignores_unrelated_dirty_files_and_enforces_ownership() {
        let repository = TestRepository::new();
        std::fs::write(repository.path().join("flake.nix"), b"{ dirty = true; }\n")
            .expect("dirty unrelated file");
        let runner = SystemCommandRunner;

        let mut transaction =
            Transaction::begin_scoped(repository.repository(), &runner, ["nix/pins/example.json"])
                .expect("unrelated dirty file is outside the selected scope");
        assert!(matches!(
            transaction.replace("flake.nix", b"{}\n"),
            Err(UpdateError::UnmanagedPath(path)) if path == Path::new("flake.nix")
        ));
        transaction.commit().expect("commit scoped transaction");

        let error = Transaction::begin_scoped(repository.repository(), &runner, ["flake.nix"])
            .err()
            .expect("selected dirty file must be rejected");
        assert!(matches!(
            error,
            UpdateError::DirtyManagedFiles { kind: "unstaged" }
        ));
    }

    #[test]
    fn staged_managed_files_are_rejected_and_failed_begin_releases_lock() {
        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/example.json");
        std::fs::write(&pin, b"{\"staged\":true}\n").expect("change pin");
        run_git(repository.path(), ["add", "nix/pins/example.json"]);
        let runner = SystemCommandRunner;

        let error = Transaction::begin(repository.repository(), &runner)
            .err()
            .expect("staged transaction should fail");
        assert!(matches!(
            error,
            UpdateError::DirtyManagedFiles { kind: "staged" }
        ));

        run_git(
            repository.path(),
            ["reset", "-q", "HEAD", "--", "nix/pins/example.json"],
        );
        run_git(
            repository.path(),
            ["checkout", "-q", "--", "nix/pins/example.json"],
        );
        Transaction::begin(repository.repository(), &runner)
            .expect("failed begin should release lock");
    }

    #[test]
    fn git_diff_execution_failure_is_not_reported_as_dirty() {
        let error = check_managed_files_clean(
            Path::new("/unused"),
            &FailingDiffRunner,
            &[PathBuf::from("nix/pins/example.json")],
        )
        .expect_err("git failure should propagate");

        assert!(matches!(
            error,
            UpdateError::CommandFailed {
                status,
                stderr,
                ..
            } if status == "128" && stderr == "fatal: repository unavailable"
        ));
    }

    #[test]
    fn rollback_restores_preexisting_untracked_pin() {
        let repository = TestRepository::new();
        let pin = repository.path().join("nix/pins/untracked.json");
        std::fs::write(&pin, b"{\"hash\":\"original\"}\n").expect("untracked pin");
        let runner = SystemCommandRunner;

        {
            let _transaction =
                Transaction::begin(repository.repository(), &runner).expect("begin transaction");
            std::fs::write(&pin, b"{\"hash\":\"external-change\"}\n")
                .expect("change untracked pin");
        }

        assert_eq!(
            std::fs::read(pin).expect("restored untracked pin"),
            b"{\"hash\":\"original\"}\n"
        );
    }

    #[test]
    fn concurrent_transaction_is_rejected_and_unmanaged_write_is_rejected() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let first =
            Transaction::begin(repository.repository(), &runner).expect("first transaction");

        let error = Transaction::begin(repository.repository(), &runner)
            .err()
            .expect("second transaction should fail");
        assert!(matches!(error, UpdateError::AlreadyRunning));

        let mut first = first;
        assert!(matches!(
            first.replace("README.md", b"no"),
            Err(UpdateError::UnmanagedPath(_))
        ));
        assert!(matches!(
            first.replace("../nix/pins/escape.json", b"no"),
            Err(UpdateError::UnsafeManagedPath(_))
        ));
        assert!(matches!(
            first.replace(repository.path().join("nix/pins/escape.json"), b"no"),
            Err(UpdateError::UnsafeManagedPath(_))
        ));
    }

    #[cfg(unix)]
    #[test]
    fn symlink_target_and_parent_are_rejected() {
        use std::os::unix::fs::symlink;

        let target_repository = TestRepository::new();
        let outside = tempfile::tempdir().expect("outside directory");
        let target = target_repository.path().join("nix/pins/example.json");
        std::fs::remove_file(&target).expect("remove target");
        symlink(outside.path().join("outside.json"), &target).expect("target symlink");
        run_git(target_repository.path(), ["add", "nix/pins/example.json"]);
        run_git(
            target_repository.path(),
            ["commit", "-q", "-m", "replace fixture with symlink"],
        );
        let runner = SystemCommandRunner;
        assert!(matches!(
            Transaction::begin(target_repository.repository(), &runner),
            Err(UpdateError::UnsafeManagedPath(_))
        ));

        let parent_repository = TestRepository::new();
        run_git(
            parent_repository.path(),
            ["rm", "-q", "nix/pins/example.json"],
        );
        run_git(
            parent_repository.path(),
            ["commit", "-q", "-m", "remove fixture pin"],
        );
        std::fs::create_dir_all(parent_repository.path().join("nix"))
            .expect("restore parent directory");
        symlink(outside.path(), parent_repository.path().join("nix/pins")).expect("parent symlink");
        let mut transaction =
            Transaction::begin(parent_repository.repository(), &runner).expect("begin transaction");
        assert!(matches!(
            transaction.replace("nix/pins/created.json", b"no"),
            Err(UpdateError::UnsafeManagedPath(_))
        ));
        assert!(!outside.path().join("created.json").exists());
    }

    #[test]
    fn repository_discovery_uses_the_absolute_git_directory() {
        let repository = TestRepository::new();
        let discovered = Repository::discover_in(&SystemCommandRunner, repository.path())
            .expect("discover repository");

        assert_eq!(discovered.root, repository.path());
        assert_eq!(discovered.git_dir, repository.path().join(".git"));
    }

    fn run_git<const N: usize>(root: &Path, args: [&str; N]) {
        let status = Command::new("git")
            .args(["-c", "commit.gpgSign=false"])
            .args(args)
            .current_dir(root)
            .status()
            .expect("run git");
        assert!(status.success());
    }

    fn assert_no_staging_files(root: &Path) {
        let pins = std::fs::read_dir(root.join("nix/pins")).expect("read pins");
        assert!(pins.filter_map(Result::ok).all(|entry| {
            !entry
                .file_name()
                .to_string_lossy()
                .contains(".update-pins.")
        }));
    }
}
