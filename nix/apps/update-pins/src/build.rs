use std::path::Path;
use std::time::Duration;

use crate::command::{CommandOutput, CommandRunner, CommandSpec};
use crate::error::UpdateError;
use crate::pins::PinDocument;
use crate::registry::{DependencyProvenance, PackageBuildSpec};
use crate::transaction::Transaction;
use crate::value_validation::validate_sri_hash;

const BUILD_OUTPUT_LIMIT: usize = 1024 * 1024;
const BUILD_TIMEOUT: Duration = Duration::from_secs(60 * 60);

const LOCAL_PACKAGE_EXPRESSION: &str = r#"
let
  flake = builtins.getFlake (toString ./.);
  pkgs = import ./nix/lib/mk-pkgs.nix {
    inputs = flake.inputs;
  } builtins.currentSystem;
in
pkgs.dotfilesPackages.${builtins.getEnv "UPDATE_PINS_PACKAGE"}
"#;

const CANDIDATE_PACKAGE_EXPRESSION: &str = r#"
let
  flake = builtins.getFlake (toString ./.);
  pkgs = import ./nix/lib/mk-pkgs.nix {
    inputs = flake.inputs;
  } builtins.currentSystem;
  packageName = builtins.getEnv "UPDATE_PINS_PACKAGE";
  pinOverride = builtins.getEnv "UPDATE_PINS_PIN_OVERRIDE";
  dependencyHashField = builtins.getEnv "UPDATE_PINS_DEPENDENCY_HASH_FIELD";
  expectedDependencyProvenance =
    builtins.fromJSON (builtins.getEnv "UPDATE_PINS_DEPENDENCY_PROVENANCE_JSON");
  rawPin = builtins.fromJSON (builtins.getEnv "UPDATE_PINS_PIN_JSON");
in
import ./nix/apps/update-pins/candidate-package.nix {
  inherit
    pkgs
    packageName
    pinOverride
    dependencyHashField
    expectedDependencyProvenance
    rawPin
    ;
}
"#;

pub fn build_package_once<R: CommandRunner>(
    label: &str,
    package: &str,
    runner: &R,
    transaction: &Transaction<'_, R>,
) -> Result<(), UpdateError> {
    println!("{label}: building candidate package...");
    let command = local_package_command(transaction.root(), package);
    let build = runner.run_limited_with_timeout(
        &command,
        BUILD_OUTPUT_LIMIT,
        BUILD_OUTPUT_LIMIT,
        BUILD_TIMEOUT,
    )?;
    if build.success() {
        return Ok(());
    }
    let status = build
        .status
        .map_or_else(|| "signal".to_owned(), |status| status.to_string());
    let diagnostic = output_tail(&build, 10);
    Err(UpdateError::message(format!(
        "{label}: candidate package build failed with status {status}:\n{diagnostic}"
    )))
}

pub fn compute_candidate_dependency_hash<R: CommandRunner>(
    label: &str,
    build: PackageBuildSpec,
    dependencies: DependencyProvenance,
    pin: &PinDocument,
    runner: &R,
    transaction: &Transaction<'_, R>,
) -> Result<String, UpdateError> {
    let field = build.dependency_hash_field;
    println!("{label}: computing {field} (expect one failing build)...");
    let pin_json = serde_json::to_string(pin.object()).map_err(|source| {
        UpdateError::message(format!(
            "{label}: failed to serialize candidate pin for {field}: {source}"
        ))
    })?;
    let command = candidate_package_command(transaction.root(), build, dependencies, &pin_json)?;
    let build = run_build(runner, &command)?;
    match build.status {
        Some(0) => {
            return Err(UpdateError::message(format!(
                "{label}: expected the candidate build for {field} to fail with a hash mismatch"
            )));
        }
        Some(_) => {}
        None => {
            return Err(UpdateError::message(format!(
                "{label}: candidate build for {field} was terminated before reporting a hash mismatch"
            )));
        }
    }
    let hash = parse_mismatch_hash(&build).map_err(|reason| {
        let diagnostic = output_tail(&build, 10);
        UpdateError::message(format!(
            "{label}: failed to refresh {field} from candidate build output ({reason}):\n{diagnostic}"
        ))
    })?;
    validate_sri_hash(&format!("{label}: {field}"), &hash)?;
    Ok(hash)
}

fn run_build<R: CommandRunner>(
    runner: &R,
    command: &CommandSpec,
) -> Result<CommandOutput, UpdateError> {
    runner.run_limited_with_timeout(
        command,
        BUILD_OUTPUT_LIMIT,
        BUILD_OUTPUT_LIMIT,
        BUILD_TIMEOUT,
    )
}

fn local_package_command(root: &Path, package: &str) -> CommandSpec {
    CommandSpec::new("nix")
        .args([
            "build",
            "--impure",
            "--expr",
            LOCAL_PACKAGE_EXPRESSION,
            "--no-link",
        ])
        .env("UPDATE_PINS_PACKAGE", package)
        .current_dir(root)
}

fn candidate_package_command(
    root: &Path,
    build: PackageBuildSpec,
    dependencies: DependencyProvenance,
    pin_json: &str,
) -> Result<CommandSpec, UpdateError> {
    validate_build_spec(build)?;
    let dependency_provenance_json =
        serde_json::to_string(&dependencies.nix_contract()).map_err(|source| {
            UpdateError::message(format!(
                "update-pins: failed to serialize dependency provenance: {source}"
            ))
        })?;
    Ok(CommandSpec::new("nix")
        .args([
            "build",
            "--impure",
            "--expr",
            CANDIDATE_PACKAGE_EXPRESSION,
            "--no-link",
        ])
        .env("UPDATE_PINS_PACKAGE", build.package_attr)
        .env("UPDATE_PINS_PIN_OVERRIDE", build.pin_override)
        .env(
            "UPDATE_PINS_DEPENDENCY_HASH_FIELD",
            build.dependency_hash_field,
        )
        .env(
            "UPDATE_PINS_DEPENDENCY_PROVENANCE_JSON",
            dependency_provenance_json,
        )
        .env("UPDATE_PINS_PIN_JSON", pin_json)
        .current_dir(root))
}

fn validate_build_spec(build: PackageBuildSpec) -> Result<(), UpdateError> {
    for (field, value) in [
        ("package attribute", build.package_attr),
        ("pin override", build.pin_override),
        ("dependency hash field", build.dependency_hash_field),
    ] {
        if value.is_empty()
            || value.len() > 128
            || !value
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
        {
            return Err(UpdateError::message(format!(
                "update-pins: unsafe {field} selector in package build specification"
            )));
        }
    }
    Ok(())
}

fn parse_mismatch_hash(output: &CommandOutput) -> Result<String, &'static str> {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let got_lines: Vec<_> = stderr
        .lines()
        .map(str::trim)
        .map(|line| line.strip_prefix('>').map_or(line, str::trim))
        .filter_map(|line| line.strip_prefix("got:").map(str::trim))
        .collect();
    let candidate = match got_lines.as_slice() {
        [candidate] => *candidate,
        [] => return Err("expected exactly one 'got: sha256-...' line, found none"),
        _ => return Err("expected exactly one 'got: sha256-...' line, found multiple"),
    };
    let mut words = candidate.split_whitespace();
    let hash = words
        .next()
        .ok_or("the 'got:' line did not contain a hash")?;
    if words.next().is_some()
        || !hash.starts_with("sha256-")
        || !hash
            .bytes()
            .skip("sha256-".len())
            .all(|byte| byte.is_ascii_alphanumeric() || b"+/=_-".contains(&byte))
        || hash.len() == "sha256-".len()
    {
        return Err("the 'got:' line did not contain one valid sha256 SRI hash");
    }
    validate_sri_hash("Nix hash mismatch", hash)
        .map_err(|_| "the 'got:' line did not contain one valid sha256 SRI hash")?;
    Ok(hash.to_owned())
}

fn output_text(output: &CommandOutput) -> String {
    let mut combined = String::from_utf8_lossy(&output.stdout).into_owned();
    if !combined.is_empty() && !combined.ends_with('\n') && !output.stderr.is_empty() {
        combined.push('\n');
    }
    combined.push_str(&String::from_utf8_lossy(&output.stderr));
    combined
}

fn output_tail(output: &CommandOutput, line_count: usize) -> String {
    let combined = output_text(output);
    let lines: Vec<_> = combined.lines().collect();
    let tail = lines[lines.len().saturating_sub(line_count)..].join("\n");
    let mut bounded: Vec<_> = tail.chars().rev().take(4096).collect();
    bounded.reverse();
    bounded.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};

    use super::{
        CANDIDATE_PACKAGE_EXPRESSION, LOCAL_PACKAGE_EXPRESSION, candidate_package_command,
        local_package_command, output_tail, parse_mismatch_hash,
    };
    use crate::command::{CommandOutput, CommandSpec};
    use crate::registry::{
        DependencyProvenance, DependencyScope, PackageBuildSpec, PairedSource, PnpmMajor,
    };

    fn dependencies() -> DependencyProvenance {
        DependencyProvenance::UpstreamPnpm {
            source: PairedSource {
                repository: "owner/repo",
                input: "demo-src",
            },
            lock_path: "pnpm-lock.yaml",
            workspace_path: "pnpm-workspace.yaml",
            workspace: "difit",
            pnpm: PnpmMajor::V11,
            scope: DependencyScope::Production,
        }
    }

    fn output(stdout: &[u8], stderr: &[u8]) -> CommandOutput {
        CommandOutput {
            status: Some(1),
            stdout: stdout.to_vec(),
            stderr: stderr.to_vec(),
        }
    }

    #[test]
    fn parses_current_and_nested_nix_hash_mismatch_diagnostics() {
        for fixture in [
            include_bytes!("fixtures/nix-hash-mismatch.stderr").as_slice(),
            include_bytes!("fixtures/nix-hash-mismatch-nested.stderr").as_slice(),
        ] {
            assert_eq!(
                parse_mismatch_hash(&output(b"", fixture)),
                Ok("sha256-4comrrEpnH4q9U7NNmk7Pr7Fmfh7EVSMSYQojwv5UcM=".to_owned())
            );
        }
    }

    #[test]
    fn rejects_missing_malformed_and_ambiguous_hashes() {
        assert!(parse_mismatch_hash(&output(b"", b"builder failed")).is_err());
        assert!(parse_mismatch_hash(&output(b"got: sha256-stdout", b"builder failed")).is_err());
        assert!(parse_mismatch_hash(&output(b"", b"got: sha512-wrong")).is_err());
        assert!(parse_mismatch_hash(&output(b"", b"got: sha256-valid")).is_err());
        assert!(parse_mismatch_hash(&output(b"", b"got: sha256-good trailing")).is_err());
        assert!(
            parse_mismatch_hash(&output(b"", b"got: sha256-first\ngot: sha256-second\n")).is_err()
        );
        assert!(
            parse_mismatch_hash(&output(
                b"",
                b"got: sha256-valid\ngot: sha256-invalid trailing\n"
            ))
            .is_err()
        );
        assert!(
            parse_mismatch_hash(&output(b"", b"got: sha256-valid\ngot: sha512-other\n")).is_err()
        );
        assert!(
            parse_mismatch_hash(&output(
                b"",
                include_bytes!("fixtures/nix-hash-mismatch-legacy-wanted.stderr")
            ))
            .is_err()
        );
        assert!(
            parse_mismatch_hash(&output(
                b"",
                include_bytes!("fixtures/nix-hash-mismatch-multiple.stderr")
            ))
            .is_err()
        );
    }

    #[test]
    fn package_selection_uses_environment_not_expression_interpolation() {
        let command = local_package_command(Path::new("/repo"), "shellfirm");
        assert_eq!(
            command,
            CommandSpec::new("nix")
                .args([
                    "build",
                    "--impure",
                    "--expr",
                    LOCAL_PACKAGE_EXPRESSION,
                    "--no-link",
                ])
                .env("UPDATE_PINS_PACKAGE", "shellfirm")
                .current_dir(PathBuf::from("/repo"))
        );
        assert!(
            LOCAL_PACKAGE_EXPRESSION
                .contains(r#"pkgs.dotfilesPackages.${builtins.getEnv "UPDATE_PINS_PACKAGE"}"#)
        );
        assert!(!LOCAL_PACKAGE_EXPRESSION.contains("shellfirm"));
    }

    #[test]
    fn candidate_build_injects_fake_hash_without_interpolating_pin_data() {
        let pin_json = r#"{"pnpmDepsHash":"sha256-private"}"#;
        let build = PackageBuildSpec {
            package_attr: "difit",
            pin_override: "difitPin",
            dependency_hash_field: "pnpmDepsHash",
        };
        let command =
            candidate_package_command(Path::new("/repo"), build, dependencies(), pin_json)
                .expect("valid spec");
        assert_eq!(
            command,
            CommandSpec::new("nix")
                .args([
                    "build",
                    "--impure",
                    "--expr",
                    CANDIDATE_PACKAGE_EXPRESSION,
                    "--no-link",
                ])
                .env("UPDATE_PINS_PACKAGE", "difit")
                .env("UPDATE_PINS_PIN_OVERRIDE", "difitPin")
                .env("UPDATE_PINS_DEPENDENCY_HASH_FIELD", "pnpmDepsHash")
                .env(
                    "UPDATE_PINS_DEPENDENCY_PROVENANCE_JSON",
                    r#"{"kind":"upstream-pnpm","lockPath":"pnpm-lock.yaml","workspacePath":"pnpm-workspace.yaml","workspace":"difit","pnpmMajor":11,"scope":"production"}"#,
                )
                .env("UPDATE_PINS_PIN_JSON", pin_json)
                .current_dir(PathBuf::from("/repo"))
        );
        assert!(
            CANDIDATE_PACKAGE_EXPRESSION
                .contains("import ./nix/apps/update-pins/candidate-package.nix")
        );
        assert!(
            CANDIDATE_PACKAGE_EXPRESSION
                .contains(r#"builtins.getEnv "UPDATE_PINS_DEPENDENCY_PROVENANCE_JSON""#)
        );
        assert!(!CANDIDATE_PACKAGE_EXPRESSION.contains("package.override"));
        assert!(!CANDIDATE_PACKAGE_EXPRESSION.contains("difit"));
        assert!(!CANDIDATE_PACKAGE_EXPRESSION.contains("difitPin"));
        assert!(!CANDIDATE_PACKAGE_EXPRESSION.contains("pnpmDepsHash"));
        assert!(!CANDIDATE_PACKAGE_EXPRESSION.contains("sha256-private"));
    }

    #[test]
    fn candidate_build_rejects_unsafe_registry_selectors() {
        for build in [
            PackageBuildSpec {
                package_attr: "",
                pin_override: "difitPin",
                dependency_hash_field: "pnpmDepsHash",
            },
            PackageBuildSpec {
                package_attr: "difit;builtins.abort",
                pin_override: "difitPin",
                dependency_hash_field: "pnpmDepsHash",
            },
            PackageBuildSpec {
                package_attr: "difit",
                pin_override: "difitPin",
                dependency_hash_field: "pnpm deps hash",
            },
        ] {
            assert!(
                candidate_package_command(Path::new("/repo"), build, dependencies(), "{}").is_err()
            );
        }
    }

    #[test]
    fn diagnostics_are_bounded_by_lines_and_characters() {
        let diagnostic = output_tail(
            &output(b"", format!("old\n{}\nlast", "x".repeat(5000)).as_bytes()),
            2,
        );
        assert!(diagnostic.chars().count() <= 4096);
        assert!(diagnostic.ends_with("last"));
        assert!(!diagnostic.contains("old"));
    }
}
