use std::collections::BTreeSet;
use std::ffi::OsString;
use std::path::PathBuf;

use crate::model::OperatorGroup;

pub const USAGE: &str = r#"Usage:
  nix-mutation-test [options] --test-command COMMAND TARGET...
  nix-mutation-test [options] --list TARGET...

Options:
  --root PATH          Repository root copied for each mutation (default: current directory)
  --test-command CMD   Command run from the temporary repository root
  --operator NAME      Select boolean, logical, or equality; repeatable (default: all)
  --max-mutants N      Test at most N mutants after deterministic sorting
  --timeout SECONDS    Per-command timeout (default: 60)
  --list               Print candidate mutants as JSON lines without running tests
  -h, --help           Show this help

Test command environment:
  NIX_MUTATION_ID      Deterministic ID for the current source, or "baseline"
  NIX_MUTATION_KIND    Mutation kind, or "baseline" for the baseline run
  NIX_MUTATION_TARGET  Repository-relative target path; empty for the baseline run

Source annotations:
  # nix-mutation-test: ignore
                       Ignore mutation candidates on that line

Exit status:
  0  Every executed valid mutant was killed, --list completed, or help was shown
  1  At least one mutant survived or timed out
  2  Invalid arguments or input, a failing or timed-out baseline, or a runner error
"#;

#[derive(Debug, Eq, PartialEq)]
pub struct Options {
    pub root: PathBuf,
    pub test_command: Option<String>,
    pub selected_operators: BTreeSet<OperatorGroup>,
    pub max_mutants: Option<usize>,
    pub timeout_seconds: u64,
    pub list_only: bool,
    pub targets: Vec<PathBuf>,
}

pub enum ParseResult {
    Options(Options),
    Help,
}

pub fn parse(arguments: impl IntoIterator<Item = OsString>) -> Result<ParseResult, String> {
    let arguments = arguments.into_iter().collect::<Vec<_>>();
    let mut index = 0;
    let mut root = PathBuf::from(".");
    let mut test_command = None;
    let mut selected_operators = BTreeSet::new();
    let mut max_mutants = None;
    let mut timeout_seconds = 60;
    let mut list_only = false;
    let mut targets = Vec::new();

    while index < arguments.len() {
        let argument = arguments[index]
            .to_str()
            .ok_or_else(|| "arguments must be valid UTF-8".to_owned())?;
        match argument {
            "--root" => {
                root = PathBuf::from(value_after(&arguments, index, "--root")?);
                index += 2;
            }
            "--test-command" => {
                test_command = Some(value_after(&arguments, index, "--test-command")?);
                index += 2;
            }
            "--operator" => {
                let value = value_after(&arguments, index, "--operator")?;
                let operator = OperatorGroup::parse(&value)
                    .ok_or_else(|| format!("unknown operator: {value}"))?;
                selected_operators.insert(operator);
                index += 2;
            }
            "--max-mutants" => {
                max_mutants = Some(parse_positive(
                    &value_after(&arguments, index, "--max-mutants")?,
                    "--max-mutants",
                )?);
                index += 2;
            }
            "--timeout" => {
                timeout_seconds =
                    parse_positive(&value_after(&arguments, index, "--timeout")?, "--timeout")?;
                index += 2;
            }
            "--list" => {
                list_only = true;
                index += 1;
            }
            "-h" | "--help" => return Ok(ParseResult::Help),
            "--" => {
                targets.extend(arguments[index + 1..].iter().map(PathBuf::from));
                break;
            }
            value if value.starts_with('-') => return Err(format!("unknown option: {value}")),
            _ => {
                targets.push(PathBuf::from(&arguments[index]));
                index += 1;
            }
        }
    }

    if targets.is_empty() {
        return Err("at least one target is required".to_owned());
    }
    if !list_only && test_command.is_none() {
        return Err("--test-command is required unless --list is used".to_owned());
    }

    Ok(ParseResult::Options(Options {
        root,
        test_command,
        selected_operators,
        max_mutants,
        timeout_seconds,
        list_only,
        targets,
    }))
}

fn value_after(arguments: &[OsString], index: usize, option: &str) -> Result<String, String> {
    arguments
        .get(index + 1)
        .ok_or_else(|| format!("{option} requires a value"))?
        .to_str()
        .map(ToOwned::to_owned)
        .ok_or_else(|| format!("{option} value must be valid UTF-8"))
}

fn parse_positive<T>(value: &str, option: &str) -> Result<T, String>
where
    T: std::str::FromStr + PartialOrd + From<u8>,
{
    let parsed = value
        .parse::<T>()
        .map_err(|_| format!("{option} must be a positive integer"))?;
    if parsed <= T::from(0) {
        return Err(format!("{option} must be a positive integer"));
    }
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    #[test]
    fn parses_repeatable_operators_and_limits() {
        let ParseResult::Options(options) = parse(args(&[
            "--list",
            "--operator",
            "logical",
            "--operator",
            "equality",
            "--max-mutants",
            "3",
            "target.nix",
        ]))
        .unwrap() else {
            panic!("expected options");
        };
        assert_eq!(options.max_mutants, Some(3));
        assert!(options.selected_operators.contains(&OperatorGroup::Logical));
        assert!(
            options
                .selected_operators
                .contains(&OperatorGroup::Equality)
        );
    }

    #[test]
    fn rejects_missing_test_command() {
        assert_eq!(
            parse(args(&["target.nix"])).err().as_deref(),
            Some("--test-command is required unless --list is used")
        );
    }

    #[test]
    fn help_documents_the_test_command_contract() {
        for expected in [
            "  NIX_MUTATION_ID      Deterministic ID for the current source, or \"baseline\"",
            "  NIX_MUTATION_KIND    Mutation kind, or \"baseline\" for the baseline run",
            "  NIX_MUTATION_TARGET  Repository-relative target path; empty for the baseline run",
            "  # nix-mutation-test: ignore",
            "                       Ignore mutation candidates on that line",
            "  0  Every executed valid mutant was killed, --list completed, or help was shown",
            "  1  At least one mutant survived or timed out",
            "  2  Invalid arguments or input, a failing or timed-out baseline, or a runner error",
        ] {
            assert!(USAGE.lines().any(|line| line == expected));
        }
    }
}
