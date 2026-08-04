use std::time::Duration;

use serde_json::Value;

use crate::command::{CommandSpec, SystemCommandRunner, run_checked_limited_with_timeout};
use crate::error::UpdateError;
use crate::registry::{GeneratorCommand, InputAuthority, PairedSource};
use crate::targets::{paired_input_version, update_paired_input};
use crate::transaction::{Repository, Transaction};

const SOURCE: PairedSource = PairedSource {
    repository: "owner/example",
    input: "example-src",
    authority: InputAuthority {
        source_path: "modules/features/example.nix",
        generated_flake_path: "flake.nix",
        lock_path: "flake.lock",
        generator: Some(GeneratorCommand {
            program: "nix",
            args: &["run", ".#write-flake"],
            baseline: None,
        }),
    },
};
const PIN_PATH: &str = "nix/pins/example.json";
const CANDIDATE_VERSION: &str = "9.9.9";
const COMMAND_OUTPUT_LIMIT: usize = 1024 * 1024;
const COMMAND_TIMEOUT: Duration = Duration::from_secs(15 * 60);

pub fn run() -> Result<(), UpdateError> {
    let runner = SystemCommandRunner;
    let repository = Repository::discover(&runner)?;
    let managed_paths = [
        PIN_PATH,
        SOURCE.authority.source_path,
        SOURCE.authority.generated_flake_path,
        SOURCE.authority.lock_path,
    ];
    let mut transaction = Transaction::begin_scoped(repository, &runner, managed_paths)?;
    let result = update_candidate(&runner, &mut transaction);
    match result {
        Ok(()) => transaction.commit(),
        Err(operation) => match transaction.rollback() {
            Ok(()) => Err(operation),
            Err(rollback) => Err(UpdateError::OperationAndRollback {
                operation: Box::new(operation),
                rollback: Box::new(rollback),
            }),
        },
    }
}

fn update_candidate(
    runner: &SystemCommandRunner,
    transaction: &mut Transaction<'_, SystemCommandRunner>,
) -> Result<(), UpdateError> {
    let authority = transaction.read(SOURCE.authority.source_path)?;
    let source_version = paired_input_version(
        &authority,
        SOURCE.authority.source_path,
        SOURCE.input,
        SOURCE.repository,
    )?;
    let generated = transaction.read(SOURCE.authority.generated_flake_path)?;
    let generated_version = paired_input_version(
        &generated,
        SOURCE.authority.generated_flake_path,
        SOURCE.input,
        SOURCE.repository,
    )?;
    if source_version != generated_version {
        return Err(UpdateError::message(format!(
            "fixture input mismatch: source v{source_version}, generated v{generated_version}"
        )));
    }

    update_pin(transaction)?;
    update_paired_input(SOURCE, CANDIDATE_VERSION, &authority, runner, transaction)?;

    let candidate = CommandSpec::new("nix")
        .args(["build", "--no-link", ".#future-layout-candidate"])
        .current_dir(transaction.root());
    run_checked_limited_with_timeout(
        runner,
        &candidate,
        COMMAND_OUTPUT_LIMIT,
        COMMAND_OUTPUT_LIMIT,
        COMMAND_TIMEOUT,
    )?;
    Ok(())
}

fn update_pin(transaction: &mut Transaction<'_, SystemCommandRunner>) -> Result<(), UpdateError> {
    let bytes = transaction.read(PIN_PATH)?;
    let mut document: Value = serde_json::from_slice(&bytes)
        .map_err(|source| UpdateError::message(format!("{PIN_PATH}: invalid JSON: {source}")))?;
    let object = document
        .as_object_mut()
        .ok_or_else(|| UpdateError::message(format!("{PIN_PATH}: expected an object")))?;
    object.insert(
        "version".to_owned(),
        Value::String(CANDIDATE_VERSION.to_owned()),
    );
    let mut rendered = serde_json::to_vec_pretty(&document).map_err(|source| {
        UpdateError::message(format!("{PIN_PATH}: failed to render JSON: {source}"))
    })?;
    rendered.push(b'\n');
    transaction.write_if_changed(PIN_PATH, &rendered)?;
    Ok(())
}
