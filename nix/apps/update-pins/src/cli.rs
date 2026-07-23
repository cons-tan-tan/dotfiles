use std::ffi::OsString;

use crate::policy::{DEFAULT_MAX_ATTEMPTS, MAX_ATTEMPTS_LIMIT, RetryPolicy, RunPolicy};
pub use crate::registry::Target;
use crate::registry::{TARGET_SPECS, target_by_name};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Invocation {
    pub target: Target,
    pub policy: RunPolicy,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ParseAction {
    Run(Invocation),
    Help,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UsageError {
    TooManyTargets,
    UnknownTarget(String),
    UnknownOption(String),
    MissingRetryValue,
    InvalidRetryValue(String),
}

impl std::fmt::Display for UsageError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TooManyTargets => formatter.write_str("update-pins: expected at most one target"),
            Self::UnknownTarget(target) => {
                write!(formatter, "update-pins: unknown target '{target}'")
            }
            Self::UnknownOption(option) => {
                write!(formatter, "update-pins: unknown option '{option}'")
            }
            Self::MissingRetryValue => {
                formatter.write_str("update-pins: --retry requires a maximum attempt count")
            }
            Self::InvalidRetryValue(value) => write!(
                formatter,
                "update-pins: --retry must be an integer from 1 to {MAX_ATTEMPTS_LIMIT}, got '{value}'"
            ),
        }
    }
}

pub fn parse_compatible_from<I, T>(arguments: I) -> Result<ParseAction, UsageError>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString>,
{
    let mut arguments = arguments.into_iter().map(Into::into);
    let _program = arguments.next();
    let mut target = None;
    let mut force = false;
    let mut max_attempts = DEFAULT_MAX_ATTEMPTS;
    while let Some(argument) = arguments.next() {
        let argument = argument.to_string_lossy();
        match argument.as_ref() {
            "--help" | "-h" => return Ok(ParseAction::Help),
            "--force" => force = true,
            "--retry" => {
                let value = arguments
                    .next()
                    .ok_or(UsageError::MissingRetryValue)?
                    .to_string_lossy()
                    .into_owned();
                max_attempts = parse_retry_value(&value)?;
            }
            value if value.starts_with("--retry=") => {
                max_attempts = parse_retry_value(&value["--retry=".len()..])?;
            }
            value if value.starts_with('-') => {
                return Err(UsageError::UnknownOption(value.to_owned()));
            }
            value => {
                let parsed = target_by_name(value)
                    .ok_or_else(|| UsageError::UnknownTarget(value.to_owned()))?;
                if target.replace(parsed).is_some() {
                    return Err(UsageError::TooManyTargets);
                }
            }
        }
    }
    Ok(ParseAction::Run(Invocation {
        target: target.unwrap_or(Target::All),
        policy: RunPolicy {
            force,
            retry: RetryPolicy::new(max_attempts)
                .expect("CLI retry bounds must produce a valid retry policy"),
        },
    }))
}

fn parse_retry_value(value: &str) -> Result<u8, UsageError> {
    value
        .parse::<u8>()
        .ok()
        .filter(|attempts| (1..=MAX_ATTEMPTS_LIMIT).contains(attempts))
        .ok_or_else(|| UsageError::InvalidRetryValue(value.to_owned()))
}

pub fn usage() -> String {
    let mut usage = String::from(
        "Usage: update-pins [--retry <MAX_ATTEMPTS>] [--force] [target]\n\n\
         Options:\n  --retry <MAX_ATTEMPTS>  Fetch attempts, including the first (1-5; default 3)\n  \
         --force                 Refresh and validate artifacts even at the same version\n\n\
         Targets:\n  all (default)\n",
    );
    for spec in TARGET_SPECS {
        usage.push_str("  ");
        usage.push_str(spec.name);
        usage.push('\n');
    }
    usage
}

#[cfg(test)]
mod tests {
    use super::{
        Invocation, ParseAction, TARGET_SPECS, Target, UsageError, parse_compatible_from, usage,
    };
    use crate::policy::{RetryPolicy, RunPolicy};

    fn invocation(target: Target) -> ParseAction {
        ParseAction::Run(Invocation {
            target,
            policy: RunPolicy::default(),
        })
    }

    #[test]
    fn compatible_parser_preserves_legacy_actions_and_errors() {
        assert_eq!(
            parse_compatible_from(["update-pins"]).expect("default target"),
            invocation(Target::All)
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "--help"]).expect("help"),
            ParseAction::Help
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "herdr"]).expect("target"),
            invocation(Target::Herdr)
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "unknown"]),
            Err(UsageError::UnknownTarget("unknown".to_owned()))
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "herdr", "hcom"]),
            Err(UsageError::TooManyTargets)
        );
    }

    #[test]
    fn compatible_parser_accepts_force_and_bounded_retry_in_any_order() {
        let expected = ParseAction::Run(Invocation {
            target: Target::Herdr,
            policy: RunPolicy {
                force: true,
                retry: RetryPolicy::new(5).expect("valid retry policy"),
            },
        });
        assert_eq!(
            parse_compatible_from(["update-pins", "--force", "--retry=5", "herdr"]),
            Ok(expected)
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "herdr", "--retry", "5", "--force"]),
            Ok(expected)
        );
        for value in ["0", "6", "-1", "many", ""] {
            assert!(matches!(
                parse_compatible_from(["update-pins", "--retry", value]),
                Err(UsageError::InvalidRetryValue(_))
            ));
        }
        assert_eq!(
            parse_compatible_from(["update-pins", "--retry"]),
            Err(UsageError::MissingRetryValue)
        );
    }

    #[test]
    fn compatible_usage_lists_targets_in_execution_order() {
        let rendered = usage();
        assert!(
            rendered
                .starts_with("Usage: update-pins [--retry <MAX_ATTEMPTS>] [--force] [target]\n")
        );
        let positions: Vec<_> = TARGET_SPECS
            .iter()
            .map(|spec| {
                rendered
                    .find(spec.name)
                    .unwrap_or_else(|| panic!("usage omitted {}", spec.name))
            })
            .collect();
        assert!(positions.windows(2).all(|pair| pair[0] < pair[1]));
    }

    #[test]
    fn compatible_parser_accepts_every_registry_name() {
        for spec in TARGET_SPECS {
            assert_eq!(
                parse_compatible_from(["update-pins", spec.name]),
                Ok(invocation(spec.target)),
                "parser and registry diverged for {}",
                spec.name
            );
        }
    }
}
