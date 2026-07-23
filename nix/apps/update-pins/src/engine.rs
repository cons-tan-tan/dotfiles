use crate::cli::Target;
use crate::command::{CommandRunner, SystemCommandRunner};
use crate::error::UpdateError;
use crate::registry::{TARGET_SPECS, target_spec, unimplemented_target_names};
use crate::targets::run_target;
use crate::transaction::{Repository, Transaction};
use crate::validation::validate_target_input;

pub fn run(target: Target) -> Result<(), UpdateError> {
    run_with_runner(target, &SystemCommandRunner)
}

pub fn run_with_runner<R: CommandRunner>(target: Target, runner: &R) -> Result<(), UpdateError> {
    let targets = selected_targets(target)?;
    let managed_paths = selected_managed_paths(&targets);
    let repository = Repository::discover(runner)?;
    let mut transaction = Transaction::begin_scoped(repository, runner, &managed_paths)?;
    for selected in &targets {
        let spec = target_spec(*selected).expect("selected targets are concrete registry entries");
        validate_target_input(spec, &transaction)?;
    }
    let mut changed = false;

    let result = targets.iter().copied().try_for_each(|target| {
        println!("== {}", target.name());
        let result = run_target(target, runner, &mut transaction)?;
        changed |= result.changed;
        Ok::<(), UpdateError>(())
    });
    let result = result.and_then(|()| {
        for selected in &targets {
            let spec =
                target_spec(*selected).expect("selected targets are concrete registry entries");
            validate_target_input(spec, &transaction)?;
        }
        Ok(())
    });

    match result {
        Ok(()) => {
            transaction.commit()?;
            println!();
            match (target, changed) {
                (Target::All, true) => println!(
                    "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit."
                ),
                (Target::All, false) => println!("All pins up to date."),
                (_, true) => println!(
                    "{} updated. Review with 'git diff', verify with 'nix run .#build', then commit.",
                    target.name()
                ),
                (_, false) => println!("{} is up to date.", target.name()),
            }
            Ok(())
        }
        Err(error) => {
            eprintln!("update-pins: failed; restoring managed files from backup");
            match transaction.rollback() {
                Ok(()) => Err(error),
                Err(rollback) => Err(UpdateError::message(format!("{error}; {rollback}"))),
            }
        }
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
    use super::{selected_managed_paths, selected_targets};
    use crate::cli::Target;
    use crate::registry::TARGET_SPECS;

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
        assert_eq!(
            selected_managed_paths(&targets),
            vec![
                "nix/pins/hcom.json",
                "flake.nix",
                "flake.lock",
                "nix/pins/agent-slack.json",
                "nix/pins/agent-browser.json",
                "nix/pins/watchexec.json",
                "nix/pins/shellfirm.json",
                "nix/pins/herdr.json",
                "nix/pins/difit.json",
                "nix/packages/difit/package-lock.json",
                "nix/pins/claude-code-settings-schema.json",
                "nix/pins/codex-app.json",
            ]
        );
    }
}
