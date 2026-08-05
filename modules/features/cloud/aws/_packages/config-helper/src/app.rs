use std::path::Path;
use std::process::Command as ProcessCommand;

use crate::cli::{Command, USAGE};
use crate::error::{AppError, Result};
use crate::filesystem::{TargetLock, create_candidate, read_required};
use crate::ini_adapter::{apply_login_update, reconcile, validate, validate_login_candidate};

pub fn execute(command: Command) -> Result<u8> {
    match command {
        Command::Help => {
            print!("{USAGE}");
            Ok(0)
        }
        Command::Login {
            aws_bin,
            baseline,
            target,
            aws_args,
        } => login(&aws_bin, &baseline, &target, &aws_args),
        Command::Reconcile {
            baseline,
            target,
            managed_sections,
        } => reconcile_target(&baseline, &target, &managed_sections),
    }
}

fn login(
    aws_bin: &Path,
    baseline_path: &Path,
    target_path: &Path,
    aws_args: &[std::ffi::OsString],
) -> Result<u8> {
    let baseline_bytes = read_required(baseline_path)?;
    let baseline = utf8(&baseline_bytes, "baseline")?;
    validate(baseline)?;

    let lock = TargetLock::acquire(target_path)?;
    let current_bytes = lock.read()?;
    let current = utf8(&current_bytes, "target")?;
    validate(current)?;

    let candidate = create_candidate(lock.directory(), &baseline_bytes)?;
    let status = ProcessCommand::new(aws_bin)
        .arg("login")
        .args(aws_args)
        .env("AWS_CONFIG_FILE", candidate.path())
        .status()
        .map_err(|error| AppError::io("execute AWS CLI", aws_bin, error))?;
    if !status.success() {
        return status
            .code()
            .and_then(|code| u8::try_from(code).ok())
            .ok_or_else(|| {
                AppError::new("aws-config-helper: AWS CLI was terminated without an exit code")
            });
    }

    let candidate_bytes = read_required(candidate.path())?;
    let candidate = utf8(&candidate_bytes, "candidate")?;
    let update = validate_login_candidate(baseline, candidate)?;
    let desired = apply_login_update(current, &update)?;
    lock.publish(desired.as_bytes())?;
    Ok(0)
}

fn reconcile_target(
    baseline_path: &Path,
    target_path: &Path,
    managed_sections: &[String],
) -> Result<u8> {
    let baseline_bytes = read_required(baseline_path)?;
    let baseline = utf8(&baseline_bytes, "baseline")?;
    validate(baseline)?;

    let lock = TargetLock::acquire(target_path)?;
    let current_bytes = lock.read()?;
    let current = utf8(&current_bytes, "target")?;
    let desired = reconcile(baseline, current, managed_sections)?;
    lock.publish(desired.as_bytes())?;
    Ok(0)
}

fn utf8<'a>(bytes: &'a [u8], role: &str) -> Result<&'a str> {
    std::str::from_utf8(bytes)
        .map_err(|_| AppError::new(format!("aws-config-helper: {role} config is not UTF-8")))
}
