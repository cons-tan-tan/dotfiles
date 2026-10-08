use std::path::Path;

use crate::cli::{Command, USAGE};
use crate::error::{AppError, Result};
use crate::filesystem::{TargetLock, read_required};
use crate::ini_adapter::{reconcile, validate};

pub fn execute(command: Command) -> Result<u8> {
    match command {
        Command::Help => {
            print!("{USAGE}");
            Ok(0)
        }
        Command::Reconcile {
            baseline,
            target,
            managed_sections,
        } => reconcile_target(&baseline, &target, &managed_sections),
    }
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
