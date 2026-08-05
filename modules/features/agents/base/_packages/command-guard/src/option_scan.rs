use std::{
    collections::{BTreeMap, BTreeSet},
    ffi::{OsStr, OsString},
};

use lexopt::Arg;

use crate::{
    error::{GuardError, Result},
    policy::OptionSyntax,
    shell::Word,
};

#[derive(Debug, Default)]
pub struct ScanResult {
    pub present: BTreeSet<String>,
    pub dynamic_relevant: bool,
}

pub fn scan(
    words: &[Word],
    syntax: &OptionSyntax,
    attached_value_options: &BTreeSet<String>,
) -> Result<ScanResult> {
    let boundary = words
        .iter()
        .position(|word| word.static_value() == Some("--"));
    let static_values = words
        .iter()
        .filter_map(Word::static_value)
        .collect::<BTreeSet<_>>();
    let mut dynamic_sentinels = BTreeMap::new();
    let mut used_sentinels = BTreeSet::new();
    let args = words
        .iter()
        .enumerate()
        .map(|(index, word)| match word.static_value() {
            Some(value) => OsString::from(value),
            None => {
                let sentinel = unique_dynamic_sentinel(index, &static_values, &mut used_sentinels);
                dynamic_sentinels.insert(sentinel.clone(), index);
                sentinel
            }
        })
        .collect::<Vec<_>>();

    let value_taking = syntax.value_taking.iter().collect::<BTreeSet<_>>();
    let optional_equals = syntax.optional_equals.iter().collect::<BTreeSet<_>>();
    let mut consumed_dynamic = BTreeSet::new();
    let mut result = ScanResult::default();
    let mut parser = lexopt::Parser::from_args(args);

    loop {
        let next = parser
            .next()
            .map_err(|error| GuardError::Options(error.to_string()))?;
        let Some(argument) = next else {
            break;
        };
        match argument {
            Arg::Long(name) => {
                let option = format!("--{name}");
                result.present.insert(option.clone());
                if value_taking.contains(&option) {
                    let value = parser
                        .value()
                        .map_err(|error| GuardError::Options(error.to_string()))?;
                    record_consumed_dynamic(&value, &dynamic_sentinels, &mut consumed_dynamic);
                } else if optional_equals.contains(&option)
                    && let Some(value) = parser.optional_value()
                {
                    record_consumed_dynamic(&value, &dynamic_sentinels, &mut consumed_dynamic);
                } else if attached_value_options.contains(&option) {
                    let _ = parser.optional_value();
                }
            }
            Arg::Short(name) => {
                let option = format!("-{name}");
                result.present.insert(option.clone());
                if value_taking.contains(&option) {
                    let value = parser
                        .value()
                        .map_err(|error| GuardError::Options(error.to_string()))?;
                    record_consumed_dynamic(&value, &dynamic_sentinels, &mut consumed_dynamic);
                } else if optional_equals.contains(&option)
                    && let Some(value) = parser.optional_value()
                {
                    record_consumed_dynamic(&value, &dynamic_sentinels, &mut consumed_dynamic);
                }
            }
            Arg::Value(value) => {
                if let Some(index) = dynamic_sentinels.get(&value).copied() {
                    let after_boundary = boundary.is_some_and(|boundary| index > boundary);
                    if !after_boundary && !consumed_dynamic.contains(&index) {
                        result.dynamic_relevant = true;
                    }
                }
            }
        }
    }
    result.dynamic_relevant |= dynamic_sentinels.values().any(|index| {
        !consumed_dynamic.contains(index) && boundary.is_none_or(|value| *index < value)
    });
    Ok(result)
}

fn unique_dynamic_sentinel(
    index: usize,
    static_values: &BTreeSet<&str>,
    used: &mut BTreeSet<OsString>,
) -> OsString {
    let mut salt = 0_usize;
    loop {
        let candidate = OsString::from(format!("__AGENT_DYNAMIC_{index}_{salt}__"));
        if !static_values.contains(candidate.to_string_lossy().as_ref())
            && used.insert(candidate.clone())
        {
            return candidate;
        }
        salt += 1;
    }
}

fn record_consumed_dynamic(
    value: &OsStr,
    sentinels: &BTreeMap<OsString, usize>,
    consumed: &mut BTreeSet<usize>,
) {
    if let Some(index) = sentinels.get(value) {
        consumed.insert(*index);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shell::{Word, WordValue};

    fn word(value: &str) -> Word {
        Word::synthetic(value)
    }

    fn dynamic() -> Word {
        Word {
            value: WordValue::Dynamic,
            source: 0..0,
        }
    }

    fn fd_syntax() -> OptionSyntax {
        OptionSyntax {
            value_taking: vec!["-E".into(), "-C".into()],
            optional_equals: vec!["--hyperlink".into()],
        }
    }

    #[test]
    fn value_taking_short_option_consumes_cluster_remainder() {
        let result = scan(&[word("-HEx")], &fd_syntax(), &BTreeSet::new()).unwrap();
        assert!(result.present.contains("-E"));
        assert!(!result.present.contains("-x"));
    }

    #[test]
    fn later_short_option_remains_visible() {
        let result = scan(&[word("-HIx")], &fd_syntax(), &BTreeSet::new()).unwrap();
        assert!(result.present.contains("-x"));
    }

    #[test]
    fn double_dash_makes_dynamic_positional_irrelevant() {
        let result = scan(&[word("--"), dynamic()], &fd_syntax(), &BTreeSet::new()).unwrap();
        assert!(!result.dynamic_relevant);
    }

    #[test]
    fn consumed_dynamic_value_is_not_an_option() {
        let result = scan(&[word("-C"), dynamic()], &fd_syntax(), &BTreeSet::new()).unwrap();
        assert!(!result.dynamic_relevant);
    }

    #[test]
    fn literal_sentinel_is_not_dynamic() {
        let result = scan(
            &[word("__AGENT_DYNAMIC_0__")],
            &fd_syntax(),
            &BTreeSet::new(),
        )
        .unwrap();
        assert!(!result.dynamic_relevant);
    }

    #[test]
    fn denial_option_consumes_only_an_attached_value() {
        let deny = BTreeSet::from(["--exec".to_owned(), "-x".to_owned()]);
        let long = scan(&[word("--exec=echo")], &fd_syntax(), &deny).unwrap();
        let short = scan(&[word("-xecho")], &fd_syntax(), &deny).unwrap();
        assert!(long.present.contains("--exec"));
        assert!(short.present.contains("-x"));
    }
}
