use crate::cli::Target;
use crate::command::{CommandRunner, SystemCommandRunner};
use crate::error::UpdateError;
use crate::registry::unimplemented_target_names;
use crate::targets::{is_implemented, run_target};
use crate::transaction::{Repository, Transaction};

pub fn run(target: Target) -> Result<(), UpdateError> {
    run_with_runner(target, &SystemCommandRunner)
}

pub fn run_with_runner<R: CommandRunner>(target: Target, runner: &R) -> Result<(), UpdateError> {
    if target == Target::All {
        let incomplete = unimplemented_target_names();
        return if incomplete.is_empty() {
            Err(UpdateError::message(
                "update-pins: Rust all-target execution is disabled until parity cutover",
            ))
        } else {
            Err(UpdateError::message(format!(
                "update-pins: Rust updater is incomplete; unimplemented targets: {}",
                incomplete.join(", ")
            )))
        };
    }
    if !is_implemented(target) {
        return Err(UpdateError::message(format!(
            "update-pins: Rust updater for {} is not yet implemented",
            target.name()
        )));
    }

    let repository = Repository::discover(runner)?;
    let mut transaction = Transaction::begin(repository, runner)?;
    println!("== {}", target.name());
    match run_target(target, runner, &mut transaction) {
        Ok(result) => {
            transaction.commit()?;
            println!();
            if result.changed {
                println!(
                    "{} updated. Review with 'git diff', verify with 'nix run .#build', then commit.",
                    target.name()
                );
            } else {
                println!("{} is up to date.", target.name());
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

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::run_with_runner;
    use crate::cli::Target;
    use crate::command::{CommandOutput, CommandRunner, CommandSpec};
    use crate::error::UpdateError;

    struct NoCommands;

    impl CommandRunner for NoCommands {
        fn run(&self, _command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            panic!("all-target preflight must not execute commands")
        }

        fn is_available(&self, _program: &Path) -> bool {
            false
        }
    }

    #[test]
    fn all_preflight_stays_disabled_until_parity_cutover() {
        let error = run_with_runner(Target::All, &NoCommands).expect_err("all remains disabled");
        assert_eq!(
            error.to_string(),
            "update-pins: Rust all-target execution is disabled until parity cutover"
        );
    }
}
