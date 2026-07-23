use std::ffi::OsString;

use crate::policy::{
    AssetJobsPolicy, DEFAULT_ASSET_JOBS, DEFAULT_MAX_ATTEMPTS, MAX_ASSET_JOBS_LIMIT,
    MAX_ATTEMPTS_LIMIT, RetryPolicy, RunPolicy,
};
pub use crate::registry::Target;
use crate::registry::{TARGET_SPECS, target_by_name};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Invocation {
    pub target: Target,
    pub policy: RunPolicy,
    pub publish_mode: PublishMode,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum PublishMode {
    #[default]
    Apply,
    Check,
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
    MissingJobsValue,
    InvalidJobsValue(String),
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
            Self::MissingJobsValue => {
                formatter.write_str("update-pins: --jobs requires a maximum job count")
            }
            Self::InvalidJobsValue(value) => write!(
                formatter,
                "update-pins: --jobs must be an integer from 1 to {MAX_ASSET_JOBS_LIMIT}, got '{value}'"
            ),
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
    let mut publish_mode = PublishMode::default();
    let mut max_asset_jobs = DEFAULT_ASSET_JOBS;
    let mut max_attempts = DEFAULT_MAX_ATTEMPTS;
    while let Some(argument) = arguments.next() {
        let argument = argument.to_string_lossy();
        match argument.as_ref() {
            "--help" | "-h" => return Ok(ParseAction::Help),
            "--force" => force = true,
            "--check" => publish_mode = PublishMode::Check,
            "--jobs" => {
                let value = arguments
                    .next()
                    .ok_or(UsageError::MissingJobsValue)?
                    .to_string_lossy()
                    .into_owned();
                max_asset_jobs = parse_jobs_value(&value)?;
            }
            value if value.starts_with("--jobs=") => {
                max_asset_jobs = parse_jobs_value(&value["--jobs=".len()..])?;
            }
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
            asset_jobs: AssetJobsPolicy::new(max_asset_jobs)
                .expect("CLI asset job bounds must produce a valid asset jobs policy"),
        },
        publish_mode,
    }))
}

fn parse_jobs_value(value: &str) -> Result<u8, UsageError> {
    value
        .parse::<u8>()
        .ok()
        .filter(|jobs| (1..=MAX_ASSET_JOBS_LIMIT).contains(jobs))
        .ok_or_else(|| UsageError::InvalidJobsValue(value.to_owned()))
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
        "Usage: update-pins [--check] [--force] [--jobs N] [--retry N] [target]\n\n\
         Options:\n  --check                 Run updates and validation, then restore repository files\n  \
         --force                 Refresh and validate artifacts even at the same version\n  \
         --jobs N                Maximum parallel jobs for release asset prefetch only (1-4; default 1)\n  \
         --retry N               Fetch attempts, including the first (1-5; default 3)\n\n\
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
        Invocation, ParseAction, PublishMode, TARGET_SPECS, Target, UsageError,
        parse_compatible_from, usage,
    };
    use crate::policy::{AssetJobsPolicy, RetryPolicy, RunPolicy};

    fn invocation(target: Target) -> ParseAction {
        ParseAction::Run(Invocation {
            target,
            policy: RunPolicy::default(),
            publish_mode: PublishMode::Apply,
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
    fn compatible_parser_accepts_force_retry_and_jobs_in_any_order() {
        let expected = ParseAction::Run(Invocation {
            target: Target::Herdr,
            policy: RunPolicy {
                force: true,
                retry: RetryPolicy::new(5).expect("valid retry policy"),
                asset_jobs: AssetJobsPolicy::new(4).expect("valid asset jobs policy"),
            },
            publish_mode: PublishMode::Apply,
        });
        assert_eq!(
            parse_compatible_from([
                "update-pins",
                "--force",
                "--jobs",
                "4",
                "--retry=5",
                "herdr",
            ]),
            Ok(expected)
        );
        assert_eq!(
            parse_compatible_from([
                "update-pins",
                "herdr",
                "--retry",
                "5",
                "--jobs=4",
                "--force",
            ]),
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
    fn compatible_parser_accepts_check_in_any_order_and_repeatedly() {
        let expected = ParseAction::Run(Invocation {
            target: Target::Herdr,
            policy: RunPolicy {
                force: true,
                ..RunPolicy::default()
            },
            publish_mode: PublishMode::Check,
        });
        assert_eq!(
            parse_compatible_from(["update-pins", "--check", "--force", "herdr"]),
            Ok(expected)
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "herdr", "--force", "--check", "--check",]),
            Ok(expected)
        );
    }

    #[test]
    fn compatible_parser_accepts_bounded_jobs_and_rejects_invalid_values() {
        for value in ["1", "4"] {
            let parsed = parse_compatible_from(["update-pins", "--jobs", value])
                .expect("valid asset job count");
            let ParseAction::Run(invocation) = parsed else {
                panic!("jobs must produce a runnable invocation");
            };
            assert_eq!(
                invocation.policy.asset_jobs.max_jobs(),
                value.parse::<usize>().expect("numeric fixture")
            );
        }
        for value in ["0", "5", "-1", "many", ""] {
            assert!(matches!(
                parse_compatible_from(["update-pins", "--jobs", value]),
                Err(UsageError::InvalidJobsValue(_))
            ));
        }
        assert_eq!(
            parse_compatible_from(["update-pins", "--jobs"]),
            Err(UsageError::MissingJobsValue)
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "--jobs="]),
            Err(UsageError::InvalidJobsValue(String::new()))
        );
    }

    #[test]
    fn compatible_usage_lists_targets_in_execution_order() {
        let rendered = usage();
        assert!(rendered.starts_with(
            "Usage: update-pins [--check] [--force] [--jobs N] [--retry N] [target]\n"
        ));
        assert!(rendered.contains("--check"));
        assert!(rendered.contains("release asset prefetch only"));
        assert!(rendered.contains("1-4; default 1"));
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
