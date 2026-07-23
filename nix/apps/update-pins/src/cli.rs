use std::ffi::OsString;

pub use crate::registry::Target;
use crate::registry::{TARGET_SPECS, target_by_name};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ParseAction {
    Run(Target),
    Help,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum UsageError {
    TooManyTargets,
    UnknownTarget(String),
}

impl std::fmt::Display for UsageError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TooManyTargets => formatter.write_str("update-pins: expected at most one target"),
            Self::UnknownTarget(target) => {
                write!(formatter, "update-pins: unknown target '{target}'")
            }
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
    let Some(target) = arguments.next() else {
        return Ok(ParseAction::Run(Target::All));
    };
    if arguments.next().is_some() {
        return Err(UsageError::TooManyTargets);
    }
    let target = target.to_string_lossy();
    if target == "--help" || target == "-h" {
        return Ok(ParseAction::Help);
    }
    target_by_name(&target)
        .map(ParseAction::Run)
        .ok_or_else(|| UsageError::UnknownTarget(target.into_owned()))
}

pub fn usage() -> String {
    let mut usage = String::from("Usage: update-pins [target]\n\nTargets:\n  all (default)\n");
    for spec in TARGET_SPECS {
        usage.push_str("  ");
        usage.push_str(spec.name);
        usage.push('\n');
    }
    usage
}

#[cfg(test)]
mod tests {
    use super::{ParseAction, TARGET_SPECS, Target, UsageError, parse_compatible_from, usage};

    #[test]
    fn compatible_parser_preserves_legacy_actions_and_errors() {
        assert_eq!(
            parse_compatible_from(["update-pins"]).expect("default target"),
            ParseAction::Run(Target::All)
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "--help"]).expect("help"),
            ParseAction::Help
        );
        assert_eq!(
            parse_compatible_from(["update-pins", "herdr"]).expect("target"),
            ParseAction::Run(Target::Herdr)
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
    fn compatible_usage_lists_targets_in_execution_order() {
        let rendered = usage();
        assert!(rendered.starts_with("Usage: update-pins [target]\n"));
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
                Ok(ParseAction::Run(spec.target)),
                "parser and registry diverged for {}",
                spec.name
            );
        }
    }
}
