use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
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
    scan_with_arities(words, syntax, attached_value_options, &BTreeMap::new())
}

pub fn scan_with_arities(
    words: &[Word],
    syntax: &OptionSyntax,
    attached_value_options: &BTreeSet<String>,
    known_arities: &BTreeMap<String, usize>,
) -> Result<ScanResult> {
    let mut boundaries = words
        .iter()
        .enumerate()
        .filter_map(|(index, word)| (word.static_value() == Some("--")).then_some(index))
        .collect::<VecDeque<_>>();
    let static_values = words
        .iter()
        .filter_map(Word::static_value)
        .collect::<BTreeSet<_>>();
    let mut dynamic_sentinels = BTreeMap::new();
    let may_split_dynamic = words
        .iter()
        .enumerate()
        .filter_map(|(index, word)| word.may_split().then_some(index))
        .collect::<BTreeSet<_>>();
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
    let mut boundary_is_trustworthy = true;
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
                boundary_is_trustworthy &= known_arities.contains_key(&option)
                    || value_taking.contains(&option)
                    || optional_equals.contains(&option)
                    || attached_value_options.contains(&option);
                let arity = known_arities
                    .get(&option)
                    .copied()
                    .unwrap_or_default()
                    .max(usize::from(value_taking.contains(&option)));
                if arity > 0 {
                    consume_values(
                        &mut parser,
                        arity,
                        &dynamic_sentinels,
                        &may_split_dynamic,
                        &mut consumed_dynamic,
                        &mut boundaries,
                    )?;
                } else if optional_equals.contains(&option)
                    && let Some(value) = parser.optional_value()
                {
                    record_consumed_dynamic(
                        &value,
                        &dynamic_sentinels,
                        &may_split_dynamic,
                        &mut consumed_dynamic,
                    );
                } else if attached_value_options.contains(&option) {
                    let _ = parser.optional_value();
                }
            }
            Arg::Short(name) => {
                let option = format!("-{name}");
                result.present.insert(option.clone());
                boundary_is_trustworthy &= known_arities.contains_key(&option)
                    || value_taking.contains(&option)
                    || optional_equals.contains(&option)
                    || attached_value_options.contains(&option);
                let arity = known_arities
                    .get(&option)
                    .copied()
                    .unwrap_or_default()
                    .max(usize::from(value_taking.contains(&option)));
                if arity > 0 {
                    consume_values(
                        &mut parser,
                        arity,
                        &dynamic_sentinels,
                        &may_split_dynamic,
                        &mut consumed_dynamic,
                        &mut boundaries,
                    )?;
                } else if optional_equals.contains(&option)
                    && let Some(value) = parser.optional_value()
                {
                    record_consumed_dynamic(
                        &value,
                        &dynamic_sentinels,
                        &may_split_dynamic,
                        &mut consumed_dynamic,
                    );
                }
            }
            Arg::Value(_) => {}
        }
    }
    let boundary = boundary_is_trustworthy
        .then(|| boundaries.front().copied())
        .flatten();
    result.dynamic_relevant |= dynamic_sentinels.values().any(|index| {
        !consumed_dynamic.contains(index) && boundary.is_none_or(|value| *index < value)
    });
    Ok(result)
}

fn consume_values(
    parser: &mut lexopt::Parser,
    arity: usize,
    sentinels: &BTreeMap<OsString, usize>,
    may_split: &BTreeSet<usize>,
    consumed: &mut BTreeSet<usize>,
    boundaries: &mut VecDeque<usize>,
) -> Result<()> {
    let attached = parser.optional_value();
    if let Some(value) = attached.as_ref() {
        record_consumed_dynamic(value, sentinels, may_split, consumed);
    }
    for _ in usize::from(attached.is_some())..arity {
        let value = parser
            .value()
            .map_err(|error| GuardError::Options(error.to_string()))?;
        record_consumed_dynamic(&value, sentinels, may_split, consumed);
        if value == "--" {
            let _ = boundaries.pop_front();
        }
    }
    Ok(())
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
    may_split: &BTreeSet<usize>,
    consumed: &mut BTreeSet<usize>,
) {
    if let Some(index) = sentinels.get(value)
        && !may_split.contains(index)
    {
        consumed.insert(*index);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shell::Word;

    fn word(value: &str) -> Word {
        Word::synthetic(value)
    }

    fn dynamic() -> Word {
        Word::dynamic_exactly_one()
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
    fn grammar_arity_hides_option_shaped_values() {
        let syntax = OptionSyntax {
            value_taking: vec![],
            optional_equals: vec![],
        };
        let deny = BTreeSet::from(["--danger".to_owned()]);
        let arities = BTreeMap::from([("--argstr".to_owned(), 2)]);
        let result = scan_with_arities(
            &[word("--argstr"), word("name"), word("--danger")],
            &syntax,
            &deny,
            &arities,
        )
        .unwrap();
        assert!(!result.present.contains("--danger"));
    }

    #[test]
    fn grammar_values_do_not_create_false_double_dash_boundaries() {
        let syntax = OptionSyntax {
            value_taking: vec![],
            optional_equals: vec![],
        };
        let arities = BTreeMap::from([("--argstr".to_owned(), 2)]);
        let consumed = scan_with_arities(
            &[word("--argstr"), word("name"), word("--"), dynamic()],
            &syntax,
            &BTreeSet::new(),
            &arities,
        )
        .unwrap();
        assert!(consumed.dynamic_relevant);

        let later_boundary = scan_with_arities(
            &[word("--argstr=name"), word("--"), word("--"), dynamic()],
            &syntax,
            &BTreeSet::new(),
            &arities,
        )
        .unwrap();
        assert!(!later_boundary.dynamic_relevant);
    }

    #[test]
    fn unknown_options_make_double_dash_boundaries_untrustworthy() {
        let result = scan(
            &[word("--future"), word("value"), word("--"), dynamic()],
            &fd_syntax(),
            &BTreeSet::new(),
        )
        .unwrap();
        assert!(result.dynamic_relevant);
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
