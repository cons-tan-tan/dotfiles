use crate::cli::{Invocation, PublishMode, Target};
use crate::command::{CommandRunner, SystemCommandRunner};
use crate::error::UpdateError;
use crate::ledger::Ledger;
use crate::registry::{TARGET_SPECS, target_spec, unimplemented_target_names};
use crate::targets::run_target;
use crate::transaction::{Repository, Transaction};
use crate::validation::validate_target_input;

pub fn run(invocation: Invocation) -> Result<(), UpdateError> {
    run_with_runner(invocation, &SystemCommandRunner)
}

pub fn run_with_runner<R: CommandRunner + Sync>(
    invocation: Invocation,
    runner: &R,
) -> Result<(), UpdateError> {
    // Keep target/registry errors ahead of repository discovery just as the
    // public execution path did before orchestration became test-injectable.
    selected_targets(invocation.target)?;
    let repository = Repository::discover(runner)?;
    run_in_repository(
        invocation,
        runner,
        repository,
        |selected, transaction| {
            let spec =
                target_spec(selected).expect("selected targets are concrete registry entries");
            validate_target_input(spec, transaction)
        },
        |target, policy, transaction, ledger| {
            run_target(target, policy, runner, transaction, ledger)
        },
    )
}

fn run_in_repository<'runner, R, V, U>(
    invocation: Invocation,
    runner: &'runner R,
    repository: Repository,
    mut validate: V,
    mut update: U,
) -> Result<(), UpdateError>
where
    R: CommandRunner + Sync,
    V: FnMut(Target, &Transaction<'runner, R>) -> Result<(), UpdateError>,
    U: FnMut(
        Target,
        crate::policy::RunPolicy,
        &mut Transaction<'runner, R>,
        &mut Ledger,
    ) -> Result<(), UpdateError>,
{
    let target = invocation.target;
    let targets = selected_targets(target)?;
    let managed_paths = selected_managed_paths(&targets);
    let mut transaction = Transaction::begin_scoped(repository, runner, &managed_paths)?;
    for selected in &targets {
        validate(*selected, &transaction)?;
    }
    let mut ledger = Ledger::default();

    let result = targets.iter().copied().try_for_each(|target| {
        println!("{}", target_heading(target));
        update(target, invocation.policy, &mut transaction, &mut ledger)?;
        Ok::<(), UpdateError>(())
    });
    let result = result.and_then(|()| {
        for selected in &targets {
            validate(*selected, &transaction)?;
        }
        Ok(())
    });

    match result {
        Ok(()) => finalize_success(invocation.publish_mode, target, &mut transaction, &ledger),
        Err(error) => Err(rollback_after_error(&mut transaction, &ledger, error)),
    }
}

fn finalize_success<R: CommandRunner>(
    publish_mode: PublishMode,
    target: Target,
    transaction: &mut Transaction<'_, R>,
    ledger: &Ledger,
) -> Result<(), UpdateError> {
    match publish_mode {
        PublishMode::Apply => finalize_apply(target, transaction, ledger),
        PublishMode::Check => finalize_check(target, transaction, ledger),
    }
}

fn finalize_apply<R: CommandRunner>(
    target: Target,
    transaction: &mut Transaction<'_, R>,
    ledger: &Ledger,
) -> Result<(), UpdateError> {
    let report = ledger.applied().render();
    if let Err(error) = transaction.commit() {
        return Err(rollback_after_error(transaction, ledger, error));
    }
    let changed = !ledger.is_empty();
    print_report(report);
    println!("{}", apply_summary(target, changed));
    Ok(())
}

fn target_heading(target: Target) -> String {
    format!("== {}", target.name())
}

fn apply_summary(target: Target, changed: bool) -> String {
    match (target, changed) {
        (Target::All, true) => {
            "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit."
                .to_owned()
        }
        (Target::All, false) => "All pins up to date.".to_owned(),
        (_, true) => format!(
            "{} updated. Review with 'git diff', verify with 'nix run .#build', then commit.",
            target.name()
        ),
        (_, false) => format!("{} is up to date.", target.name()),
    }
}

fn finalize_check<R: CommandRunner>(
    target: Target,
    transaction: &mut Transaction<'_, R>,
    ledger: &Ledger,
) -> Result<(), UpdateError> {
    let report = ledger.candidate().render();
    let changed = !ledger.is_empty();
    transaction
        .rollback()
        .map_err(|rollback| UpdateError::CheckRollback {
            rollback: Box::new(rollback),
        })?;
    print_report(report);
    if changed {
        println!(
            "{} check succeeded; no managed changes were kept.",
            target.name()
        );
    } else {
        println!(
            "{} check succeeded; no pin changes required.",
            target.name()
        );
    }
    Ok(())
}

fn print_report(report: Option<String>) {
    println!();
    if let Some(report) = report {
        println!("{report}");
        println!();
    }
}

fn rollback_after_error<R: CommandRunner>(
    transaction: &mut Transaction<'_, R>,
    ledger: &Ledger,
    error: UpdateError,
) -> UpdateError {
    let report = ledger.rolled_back().render();
    eprintln!("update-pins: failed; restoring managed files from backup");
    match transaction.rollback() {
        Ok(()) => {
            if let Some(report) = report {
                eprintln!("{report}");
            }
            error
        }
        Err(rollback) => UpdateError::OperationAndRollback {
            operation: Box::new(error),
            rollback: Box::new(rollback),
        },
    }
}

fn selected_targets(target: Target) -> Result<Vec<Target>, UpdateError> {
    if target == Target::All {
        let incomplete = unimplemented_target_names();
        if !incomplete.is_empty() {
            return Err(UpdateError::message(format!(
                "update-pins: Rust updater is incomplete; unimplemented targets: {}",
                incomplete.join(", ")
            )));
        }
        Ok(TARGET_SPECS.iter().map(|spec| spec.target).collect())
    } else if TARGET_SPECS.iter().any(|spec| spec.target == target) {
        Ok(vec![target])
    } else {
        Err(UpdateError::message(format!(
            "update-pins: Rust updater for {} is not yet implemented",
            target.name()
        )))
    }
}

fn selected_managed_paths(targets: &[Target]) -> Vec<&'static str> {
    let mut paths = Vec::new();
    for target in targets {
        let spec = target_spec(*target).expect("selected targets are concrete registry entries");
        for path in spec.managed_paths {
            if !paths.contains(path) {
                paths.push(*path);
            }
        }
    }
    paths
}

#[cfg(test)]
mod tests {
    use std::cell::{Cell, RefCell};
    use std::fs::Permissions;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    use tempfile::TempDir;

    use super::{
        apply_summary, run_in_repository, selected_managed_paths, selected_targets, target_heading,
    };
    use crate::cli::{Invocation, PublishMode, Target};
    use crate::command::SystemCommandRunner;
    use crate::error::UpdateError;
    use crate::ledger::{Change, ChangeKind, DisplayValue};
    use crate::policy::RunPolicy;
    use crate::registry::{TARGET_SPECS, target_spec};
    use crate::transaction::{Repository, Transaction};

    struct TestRepository {
        directory: TempDir,
        originals: Vec<(PathBuf, Vec<u8>, Permissions)>,
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
                ["config", "user.name", "update-pins engine test"],
            );
            run_git(directory.path(), ["config", "commit.gpgsign", "false"]);

            let targets = selected_targets(Target::All).expect("all targets");
            let mut originals = Vec::new();
            for relative in selected_managed_paths(&targets) {
                let path = directory.path().join(relative);
                std::fs::create_dir_all(path.parent().expect("managed path parent"))
                    .expect("managed path directory");
                let bytes = format!("original {relative}\n").into_bytes();
                std::fs::write(&path, &bytes).expect("managed fixture");
                let permissions = std::fs::metadata(&path)
                    .expect("managed fixture metadata")
                    .permissions();
                originals.push((PathBuf::from(relative), bytes, permissions));
            }
            run_git(directory.path(), ["add", "."]);
            run_git(directory.path(), ["commit", "-q", "-m", "initial"]);
            Self {
                directory,
                originals,
            }
        }

        fn path(&self) -> &Path {
            self.directory.path()
        }

        fn repository(&self) -> Repository {
            Repository::discover_in(&SystemCommandRunner, self.path())
                .expect("discover test repository")
        }

        fn assert_originals(&self) {
            for (relative, bytes, permissions) in &self.originals {
                let path = self.path().join(relative);
                assert_eq!(
                    std::fs::read(&path).expect("restored managed fixture"),
                    *bytes,
                    "{} bytes were not restored",
                    relative.display()
                );
                assert_eq!(
                    std::fs::metadata(&path)
                        .expect("restored managed fixture metadata")
                        .permissions(),
                    *permissions,
                    "{} mode was not restored",
                    relative.display()
                );
            }
        }

        fn commit_changes(&self) {
            run_git(self.path(), ["add", "."]);
            run_git(self.path(), ["commit", "-q", "-m", "updated"]);
        }

        fn assert_lock_reacquirable(&self) {
            let runner = SystemCommandRunner;
            let targets = selected_targets(Target::All).expect("all targets");
            let paths = selected_managed_paths(&targets);
            let mut transaction =
                Transaction::begin_scoped(self.repository(), &runner, paths).expect("reacquire");
            transaction.rollback().expect("release reacquired lock");
        }

        fn assert_no_staging_files(&self) {
            for (relative, _, _) in &self.originals {
                let parent = relative.parent().expect("managed path parent");
                let entries = std::fs::read_dir(self.path().join(parent))
                    .expect("read managed path directory");
                for entry in entries {
                    let entry = entry.expect("read managed path directory entry");
                    assert!(
                        !entry
                            .file_name()
                            .to_string_lossy()
                            .contains(".update-pins."),
                        "staging file remains at {}",
                        entry.path().display()
                    );
                }
            }
        }
    }

    fn invocation(target: Target, publish_mode: PublishMode) -> Invocation {
        Invocation {
            target,
            policy: RunPolicy::default(),
            publish_mode,
        }
    }

    fn record_change(target: Target, ledger: &mut crate::ledger::Ledger) {
        ledger.extend([Change {
            target,
            kind: ChangeKind::Version,
            old: DisplayValue::Text("old".to_owned()),
            new: DisplayValue::Text("new".to_owned()),
        }]);
    }

    fn run_git<I, S>(directory: &Path, arguments: I)
    where
        I: IntoIterator<Item = S>,
        S: AsRef<std::ffi::OsStr>,
    {
        let status = Command::new("git")
            .args(arguments)
            .current_dir(directory)
            .status()
            .expect("run git");
        assert!(status.success(), "git fixture command failed");
    }

    #[test]
    fn all_runs_every_target_in_registry_order() {
        assert_eq!(
            selected_targets(Target::All).expect("all targets are implemented"),
            TARGET_SPECS
                .iter()
                .map(|spec| spec.target)
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn a_single_target_remains_scoped() {
        assert_eq!(
            selected_targets(Target::Herdr).expect("herdr is implemented"),
            vec![Target::Herdr]
        );
        assert_eq!(
            selected_managed_paths(&[Target::Herdr]),
            vec!["nix/pins/herdr.json"]
        );
    }

    #[test]
    fn all_managed_paths_are_a_deterministic_registry_union() {
        let targets = selected_targets(Target::All).expect("all targets are implemented");
        let expected = TARGET_SPECS
            .iter()
            .flat_map(|spec| spec.managed_paths.iter().copied())
            .fold(Vec::new(), |mut paths, path| {
                if !paths.contains(&path) {
                    paths.push(path);
                }
                paths
            });
        let selected = selected_managed_paths(&targets);

        assert_eq!(selected, expected);
        assert!(selected.iter().all(|path| {
            TARGET_SPECS
                .iter()
                .any(|spec| spec.managed_paths.contains(path))
        }));
    }

    #[test]
    fn all_target_output_contract_is_derived_from_registry() {
        let targets = selected_targets(Target::All).expect("all targets are implemented");
        let headings = targets.into_iter().map(target_heading).collect::<Vec<_>>();
        let expected = TARGET_SPECS
            .iter()
            .map(|spec| format!("== {}", spec.name))
            .collect::<Vec<_>>();

        assert_eq!(headings, expected);
        assert_eq!(apply_summary(Target::All, false), "All pins up to date.");
    }

    #[test]
    fn all_preflights_before_updates_then_commits_in_registry_order() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let events = RefCell::new(Vec::new());
        let validation_count = Cell::new(0);
        let target_count = TARGET_SPECS.len();

        run_in_repository(
            invocation(Target::All, PublishMode::Apply),
            &runner,
            repository.repository(),
            |target, _transaction| {
                events
                    .borrow_mut()
                    .push(format!("validate:{}", target.name()));
                validation_count.set(validation_count.get() + 1);
                Ok(())
            },
            |target, _policy, transaction, ledger| {
                assert_eq!(
                    validation_count.get(),
                    target_count,
                    "every target must pass preflight before the first update"
                );
                events
                    .borrow_mut()
                    .push(format!("update:{}", target.name()));
                let changed = target_spec(target)
                    .expect("target spec")
                    .managed_paths
                    .iter()
                    .map(|path| {
                        transaction
                            .replace(path, format!("updated {path}\n").as_bytes())
                            .expect("replace managed path")
                    })
                    .fold(false, |changed, current| changed || current);
                if changed {
                    record_change(target, ledger);
                }
                Ok(())
            },
        )
        .expect("all-target apply");

        let target_names = TARGET_SPECS
            .iter()
            .map(|spec| spec.name)
            .collect::<Vec<_>>();
        let expected = target_names
            .iter()
            .map(|name| format!("validate:{name}"))
            .chain(target_names.iter().map(|name| format!("update:{name}")))
            .chain(target_names.iter().map(|name| format!("validate:{name}")))
            .collect::<Vec<_>>();
        assert_eq!(*events.borrow(), expected);
        assert_eq!(
            std::fs::read(repository.path().join("flake.lock")).expect("committed lock"),
            b"updated flake.lock\n"
        );
        repository.assert_no_staging_files();
        repository.commit_changes();
        let stable = repository
            .originals
            .iter()
            .map(|(relative, _, _)| {
                let path = repository.path().join(relative);
                (
                    relative,
                    std::fs::read(&path).expect("stable managed bytes"),
                    std::fs::metadata(&path).expect("stable managed metadata"),
                )
            })
            .collect::<Vec<_>>();

        run_in_repository(
            invocation(Target::All, PublishMode::Apply),
            &runner,
            repository.repository(),
            |_target, _transaction| Ok(()),
            |target, _policy, transaction, ledger| {
                let changed = target_spec(target)
                    .expect("target spec")
                    .managed_paths
                    .iter()
                    .map(|path| {
                        transaction
                            .replace(path, format!("updated {path}\n").as_bytes())
                            .expect("idempotent managed path")
                    })
                    .fold(false, |changed, current| changed || current);
                if changed {
                    record_change(target, ledger);
                }
                Ok(())
            },
        )
        .expect("second all-target apply");

        for (relative, stable_bytes, stable_metadata) in stable {
            let path = repository.path().join(relative);
            assert_eq!(
                std::fs::read(&path).expect("idempotent managed bytes"),
                stable_bytes,
                "{} bytes changed on the second run",
                relative.display()
            );
            let idempotent_metadata =
                std::fs::metadata(&path).expect("idempotent managed metadata");
            assert_eq!(
                idempotent_metadata.permissions(),
                stable_metadata.permissions(),
                "{} mode changed on the second run",
                relative.display()
            );
            #[cfg(unix)]
            {
                use std::os::unix::fs::MetadataExt as _;

                assert_eq!(idempotent_metadata.ino(), stable_metadata.ino());
                assert_eq!(idempotent_metadata.mtime(), stable_metadata.mtime());
                assert_eq!(
                    idempotent_metadata.mtime_nsec(),
                    stable_metadata.mtime_nsec()
                );
            }
        }
        repository.assert_no_staging_files();
        repository.assert_lock_reacquirable();
    }

    #[test]
    fn failed_all_target_preflight_runs_no_update_or_child_boundary() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        let updates = Cell::new(0);

        let error = run_in_repository(
            invocation(Target::All, PublishMode::Apply),
            &runner,
            repository.repository(),
            |target, _transaction| {
                if target == Target::Shellfirm {
                    Err(UpdateError::message("synthetic preflight failure"))
                } else {
                    Ok(())
                }
            },
            |_target, _policy, _transaction, _ledger| {
                updates.set(updates.get() + 1);
                Ok(())
            },
        )
        .expect_err("preflight must fail");

        assert_eq!(error.to_string(), "synthetic preflight failure");
        assert_eq!(updates.get(), 0);
        repository.assert_originals();
        repository.assert_lock_reacquirable();
    }

    #[test]
    fn check_restores_candidate_bytes_modes_and_transaction_lock() {
        use std::os::unix::fs::PermissionsExt as _;

        let repository = TestRepository::new();
        let runner = SystemCommandRunner;
        for relative in target_spec(Target::Hcom).expect("hcom spec").managed_paths {
            std::fs::set_permissions(
                repository.path().join(relative),
                Permissions::from_mode(0o440),
            )
            .expect("restrict managed fixture");
        }
        let expected = target_spec(Target::Hcom)
            .expect("hcom spec")
            .managed_paths
            .iter()
            .map(|relative| {
                (
                    *relative,
                    std::fs::read(repository.path().join(relative)).expect("fixture bytes"),
                )
            })
            .collect::<Vec<_>>();

        run_in_repository(
            invocation(Target::Hcom, PublishMode::Check),
            &runner,
            repository.repository(),
            |_target, _transaction| Ok(()),
            |target, _policy, transaction, ledger| {
                for relative in target_spec(target).expect("target spec").managed_paths {
                    transaction
                        .replace(relative, b"candidate\n")
                        .expect("candidate write");
                    std::fs::set_permissions(
                        repository.path().join(relative),
                        Permissions::from_mode(0o777),
                    )
                    .expect("candidate mode");
                }
                record_change(target, ledger);
                Ok(())
            },
        )
        .expect("check mode");

        for (relative, bytes) in expected {
            let path = repository.path().join(relative);
            assert_eq!(std::fs::read(&path).expect("restored bytes"), bytes);
            assert_eq!(
                std::fs::metadata(path)
                    .expect("restored metadata")
                    .permissions()
                    .mode()
                    & 0o777,
                0o440
            );
        }
        repository.assert_lock_reacquirable();
    }

    #[test]
    fn late_target_failure_restores_prior_pins_and_shared_flake_lock() {
        let repository = TestRepository::new();
        let runner = SystemCommandRunner;

        let error = run_in_repository(
            invocation(Target::All, PublishMode::Apply),
            &runner,
            repository.repository(),
            |_target, _transaction| Ok(()),
            |target, _policy, transaction, ledger| {
                for path in target_spec(target).expect("target spec").managed_paths {
                    transaction
                        .replace(path, format!("candidate {path}\n").as_bytes())
                        .expect("candidate managed path");
                }
                record_change(target, ledger);
                if target == Target::CodexApp {
                    Err(UpdateError::message("synthetic late target failure"))
                } else {
                    Ok(())
                }
            },
        )
        .expect_err("late target must fail");

        assert_eq!(error.to_string(), "synthetic late target failure");
        repository.assert_originals();
        repository.assert_no_staging_files();
        repository.assert_lock_reacquirable();
    }
}
