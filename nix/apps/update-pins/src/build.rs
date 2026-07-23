use std::path::Path;

use crate::command::{CommandOutput, CommandRunner, CommandSpec};
use crate::error::UpdateError;
use crate::pins::PinDocument;
use crate::transaction::Transaction;
use crate::validation::validate_sri_hash;

const LOCAL_PACKAGE_EXPRESSION: &str = r#"
let
  flake = builtins.getFlake (toString ./.);
  pkgs = import ./nix/lib/mk-pkgs.nix {
    inputs = flake.inputs;
  } builtins.currentSystem;
in
pkgs.dotfilesPackages.${builtins.getEnv "UPDATE_PINS_PACKAGE"}
"#;

pub fn compute_hash_via_failed_build<R: CommandRunner>(
    label: &str,
    package: &str,
    pin_path: &str,
    field: &str,
    pin: &mut PinDocument,
    runner: &R,
    transaction: &mut Transaction<'_, R>,
) -> Result<(), UpdateError> {
    println!("{label}: computing {field} (expect one failing build)...");
    let command = local_package_command(transaction.root(), package);
    let failed_build = runner.run(&command)?;
    match failed_build.status {
        Some(0) => {
            return Err(UpdateError::message(format!(
                "{label}: expected the first build for {field} to fail with a hash mismatch"
            )));
        }
        Some(_) => {}
        None => {
            return Err(UpdateError::message(format!(
                "{label}: first build for {field} was terminated before reporting a hash mismatch"
            )));
        }
    }

    let hash = parse_mismatch_hash(&failed_build).map_err(|reason| {
        let diagnostic = output_tail(&failed_build, 10);
        UpdateError::message(format!(
            "{label}: failed to extract {field} from build output ({reason}):\n{diagnostic}"
        ))
    })?;
    validate_sri_hash(&format!("{label}: {field}"), &hash)?;
    pin.set_string(&[field], &hash)?;
    if let Some(rendered) = pin.rendered()? {
        transaction.replace(pin_path, &rendered)?;
    }

    println!("{label}: verifying build...");
    let verification = runner.run(&command)?;
    if !verification.success() {
        let status = verification
            .status
            .map_or_else(|| "signal".to_owned(), |status| status.to_string());
        let diagnostic = output_tail(&verification, 10);
        return Err(UpdateError::message(format!(
            "{label}: verification build failed for {field} with status {status}:\n{diagnostic}"
        )));
    }
    Ok(())
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

fn parse_mismatch_hash(output: &CommandOutput) -> Result<String, &'static str> {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let got_lines: Vec<_> = stderr
        .lines()
        .filter_map(|line| line.trim().strip_prefix("got:").map(str::trim))
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
        LOCAL_PACKAGE_EXPRESSION, local_package_command, output_tail, parse_mismatch_hash,
    };
    use crate::command::{CommandOutput, CommandSpec};

    fn output(stdout: &[u8], stderr: &[u8]) -> CommandOutput {
        CommandOutput {
            status: Some(1),
            stdout: stdout.to_vec(),
            stderr: stderr.to_vec(),
        }
    }

    #[test]
    fn parses_one_hash_from_nix_stderr() {
        let fixture = include_bytes!("fixtures/nix-hash-mismatch.stderr");
        assert_eq!(
            parse_mismatch_hash(&output(b"", fixture)),
            Ok("sha256-4comrrEpnH4q9U7NNmk7Pr7Fmfh7EVSMSYQojwv5UcM=".to_owned())
        );
    }

    #[test]
    fn rejects_missing_malformed_and_ambiguous_hashes() {
        assert!(parse_mismatch_hash(&output(b"", b"builder failed")).is_err());
        assert!(parse_mismatch_hash(&output(b"got: sha256-stdout", b"builder failed")).is_err());
        assert!(parse_mismatch_hash(&output(b"", b"got: sha512-wrong")).is_err());
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
