use std::collections::BTreeMap;

use crate::{
    error::{GuardError, Result},
    policy::{CommandGrammar, CommandGrammarStage, SelectorKind, UnknownBehavior},
    shell::Word,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Classification {
    NotApplicable,
    Terminal,
    Canonical {
        words: Vec<Option<String>>,
        selector_indices: Vec<usize>,
    },
}

enum StageMatch {
    Matched {
        token: String,
        next_index: usize,
        selector_index: usize,
    },
    Stop,
}

enum TerminalScan {
    Absent,
    Safe,
    Ambiguous(String),
}

pub fn classify(
    executable: &str,
    words: &[Word],
    grammars: &BTreeMap<String, CommandGrammar>,
) -> Result<Classification> {
    let Some(grammar) = grammars.get(executable) else {
        return Ok(Classification::NotApplicable);
    };

    let mut canonical = vec![Some(executable.to_owned())];
    let mut path = Vec::new();
    let mut selector_indices = Vec::new();
    let mut word_index = 1;
    let mut matched_any = false;
    while let Some(stage) = grammar.stages.iter().find(|stage| stage.at == path) {
        match scan_stage(&words[word_index..], grammar, stage)? {
            StageMatch::Matched {
                token,
                next_index,
                selector_index,
            } => {
                path.push(token.clone());
                canonical.push(Some(token));
                selector_indices.push(word_index + selector_index);
                word_index += next_index;
                matched_any = true;
            }
            StageMatch::Stop => break,
        }
    }
    let terminal_words = terminal_scan_words(executable, words, grammar, &path, &selector_indices)?;
    let terminal = scan_terminal_option(terminal_words, grammar)?;
    if matches!(terminal, TerminalScan::Safe) {
        return Ok(Classification::Terminal);
    }

    if matched_any && let TerminalScan::Ambiguous(reason) = terminal {
        Err(GuardError::Policy(reason))
    } else if matched_any {
        Ok(Classification::Canonical {
            words: canonical,
            selector_indices,
        })
    } else {
        Ok(Classification::NotApplicable)
    }
}

fn terminal_scan_words<'a>(
    executable: &str,
    words: &'a [Word],
    grammar: &CommandGrammar,
    path: &[String],
    selector_indices: &[usize],
) -> Result<&'a [Word]> {
    if executable != "nix"
        || !path
            .first()
            .is_some_and(|subcommand| matches!(subcommand.as_str(), "develop" | "shell"))
    {
        return Ok(&words[1..]);
    }
    let Some(argument_start) = selector_indices.first().map(|index| index + 1) else {
        return Ok(&words[1..]);
    };
    let Some(boundary) = find_option_boundary(
        &words[argument_start..],
        grammar,
        &["-c", "--command"],
        "nix shell argument before --command",
    )?
    else {
        return Ok(&words[1..]);
    };
    Ok(&words[1..argument_start + boundary])
}

fn scan_terminal_option(words: &[Word], grammar: &CommandGrammar) -> Result<TerminalScan> {
    let mut index = 0;
    let mut ambiguity = None;
    while let Some(word) = words.get(index) {
        let Some(value) = word.static_value() else {
            ambiguity.get_or_insert_with(|| {
                "a terminal option follows a dynamic argument and cannot be safely classified"
                    .to_owned()
            });
            index += 1;
            continue;
        };
        if value == "--" {
            break;
        }
        if let Some(long) = value.strip_prefix("--") {
            let (name, attached) = long
                .split_once('=')
                .map_or((long, false), |(name, _)| (name, true));
            let option = format!("--{name}");
            if grammar.terminal_options.contains(&option) {
                return Ok(ambiguity.map_or(TerminalScan::Safe, TerminalScan::Ambiguous));
            }
            if let Some(arity) = grammar.options.get(&option).copied() {
                let Some(next) =
                    consume_terminal_option_values(words, index, arity, attached, &option)?
                else {
                    return Ok(TerminalScan::Absent);
                };
                index = next;
                continue;
            }
            if is_option_selector(grammar, &option) && !attached {
                index += 1;
                continue;
            }
            ambiguity.get_or_insert_with(|| {
                format!("a terminal option follows unknown option {option} and cannot be safely classified")
            });
            index += 1;
            continue;
        }
        if value.starts_with('-') && value.len() > 1 {
            let mut chars = value[1..].char_indices().peekable();
            let mut consumed_to = index + 1;
            while let Some((_offset, name)) = chars.next() {
                let option = format!("-{name}");
                if grammar.terminal_options.contains(&option) {
                    return Ok(ambiguity.map_or(TerminalScan::Safe, TerminalScan::Ambiguous));
                }
                if let Some(arity) = grammar.options.get(&option).copied() {
                    if arity > 0 {
                        let attached = chars.peek().is_some();
                        let Some(next) =
                            consume_terminal_option_values(words, index, arity, attached, &option)?
                        else {
                            return Ok(TerminalScan::Absent);
                        };
                        consumed_to = next;
                        break;
                    }
                    continue;
                }
                if is_option_selector(grammar, &option) {
                    continue;
                }
                ambiguity.get_or_insert_with(|| {
                    format!(
                        "a terminal option follows unknown option {option} and cannot be safely classified"
                    )
                });
            }
            index = consumed_to;
            continue;
        }
        index += 1;
    }
    Ok(TerminalScan::Absent)
}

fn is_option_selector(grammar: &CommandGrammar, option: &str) -> bool {
    grammar
        .stages
        .iter()
        .any(|stage| stage.selector == SelectorKind::Option && stage.aliases.contains_key(option))
}

fn scan_stage(
    words: &[Word],
    grammar: &CommandGrammar,
    stage: &CommandGrammarStage,
) -> Result<StageMatch> {
    let mut index = 0;
    let mut option_selector: Option<(String, usize)> = None;
    let mut deferred_unknown: Option<String> = None;
    while let Some(word) = words.get(index) {
        let Some(value) = word.static_value() else {
            if stage.selector == SelectorKind::Positional || option_selector.is_none() {
                return Err(GuardError::Policy(
                    "a command selector is dynamic and cannot be safely classified".to_owned(),
                ));
            }
            index += 1;
            continue;
        };
        if value == "--" {
            if stage.selector == SelectorKind::Option {
                break;
            }
            index += 1;
            continue;
        }
        if let Some(long) = value.strip_prefix("--") {
            let (name, attached) = long
                .split_once('=')
                .map_or((long, false), |(name, _)| (name, true));
            let option = format!("--{name}");
            if stage.selector == SelectorKind::Option
                && let Some(token) = stage.aliases.get(&option)
            {
                record_option_selector(&mut option_selector, token, index + 1)?;
                index += 1;
                continue;
            }
            if grammar.terminal_options.contains(&option) {
                index += 1;
                continue;
            }
            if let Some(arity) = grammar.options.get(&option).copied() {
                index = consume_option_values(words, index, arity, attached, &option)?;
                continue;
            }
            match stage.unknown_option {
                UnknownBehavior::Deny => {
                    let reason =
                        format!("unknown option {option} before a guarded command selector");
                    if stage.selector == SelectorKind::Positional
                        && stage.unknown_selector == UnknownBehavior::Ignore
                    {
                        deferred_unknown.get_or_insert(reason);
                        index += 1;
                        continue;
                    }
                    return Err(GuardError::Policy(reason));
                }
                UnknownBehavior::Ignore => {
                    if stage.selector == SelectorKind::Option
                        && stage.unknown_selector == UnknownBehavior::Deny
                    {
                        deferred_unknown.get_or_insert_with(|| {
                            format!("unknown command selector option {option} at {:?}", stage.at)
                        });
                    }
                    index += 1;
                    continue;
                }
            }
        }
        if value.starts_with('-') && value.len() > 1 {
            let mut chars = value[1..].char_indices().peekable();
            let mut consumed_to = index + 1;
            while let Some((_offset, name)) = chars.next() {
                let option = format!("-{name}");
                if stage.selector == SelectorKind::Option
                    && let Some(token) = stage.aliases.get(&option)
                {
                    record_option_selector(&mut option_selector, token, index + 1)?;
                    continue;
                }
                if grammar.terminal_options.contains(&option) {
                    continue;
                }
                if let Some(arity) = grammar.options.get(&option).copied() {
                    if arity > 0 {
                        let attached = chars.peek().is_some();
                        consumed_to =
                            consume_option_values(words, index, arity, attached, &option)?;
                        break;
                    }
                    continue;
                }
                if stage.unknown_option == UnknownBehavior::Deny {
                    let reason =
                        format!("unknown option {option} before a guarded command selector");
                    if stage.selector == SelectorKind::Positional
                        && stage.unknown_selector == UnknownBehavior::Ignore
                    {
                        deferred_unknown.get_or_insert(reason);
                        continue;
                    }
                    return Err(GuardError::Policy(reason));
                }
                if stage.selector == SelectorKind::Option
                    && stage.unknown_selector == UnknownBehavior::Deny
                {
                    deferred_unknown.get_or_insert_with(|| {
                        format!("unknown command selector option {option} at {:?}", stage.at)
                    });
                }
            }
            index = consumed_to;
            continue;
        }

        if stage.selector == SelectorKind::Positional {
            if let Some(token) = stage.aliases.get(value) {
                if let Some(reason) = deferred_unknown {
                    return Err(GuardError::Policy(reason));
                }
                return Ok(StageMatch::Matched {
                    token: token.clone(),
                    next_index: index + 1,
                    selector_index: index,
                });
            }
            if deferred_unknown.is_some() {
                index += 1;
                continue;
            }
            return unknown(
                stage.unknown_selector,
                &format!("unknown command selector {value:?} at {:?}", stage.at),
            );
        }
        index += 1;
    }

    if let Some((token, next_index)) = option_selector {
        Ok(StageMatch::Matched {
            token,
            selector_index: next_index - 1,
            next_index,
        })
    } else if let Some(reason) = deferred_unknown {
        if stage.selector == SelectorKind::Positional
            && stage.unknown_selector == UnknownBehavior::Ignore
        {
            Ok(StageMatch::Stop)
        } else {
            Err(GuardError::Policy(reason))
        }
    } else {
        Ok(StageMatch::Stop)
    }
}

fn record_option_selector(
    selected: &mut Option<(String, usize)>,
    token: &str,
    next_index: usize,
) -> Result<()> {
    if selected.is_some() {
        return Err(GuardError::Policy(
            "multiple operation selectors were found in one guarded command".to_owned(),
        ));
    }
    *selected = Some((token.to_owned(), next_index));
    Ok(())
}

pub(crate) fn skip_known_option(
    words: &[Word],
    option_index: usize,
    grammar: &CommandGrammar,
) -> Result<Option<usize>> {
    let value = words
        .get(option_index)
        .and_then(Word::static_value)
        .ok_or_else(|| GuardError::Policy("a command option is dynamic".to_owned()))?;
    if let Some(long) = value.strip_prefix("--") {
        let (name, attached) = long
            .split_once('=')
            .map_or((long, false), |(name, _)| (name, true));
        let option = format!("--{name}");
        let Some(arity) = grammar.options.get(&option).copied() else {
            return Ok(None);
        };
        return consume_option_values(words, option_index, arity, attached, &option).map(Some);
    }
    if !value.starts_with('-') || value == "-" {
        return Ok(None);
    }

    let mut chars = value[1..].chars().peekable();
    while let Some(name) = chars.next() {
        let option = format!("-{name}");
        let Some(arity) = grammar.options.get(&option).copied() else {
            return Ok(None);
        };
        if arity > 0 {
            return consume_option_values(
                words,
                option_index,
                arity,
                chars.peek().is_some(),
                &option,
            )
            .map(Some);
        }
    }
    Ok(Some(option_index + 1))
}

pub(crate) fn find_option_boundary(
    words: &[Word],
    grammar: &CommandGrammar,
    boundaries: &[&str],
    context: &str,
) -> Result<Option<usize>> {
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = word
            .static_value()
            .ok_or_else(|| GuardError::Policy(format!("{context} follows a dynamic argument")))?;
        if boundaries.contains(&value) {
            return Ok(Some(index));
        }
        if grammar
            .terminal_options
            .iter()
            .any(|option| option == value)
        {
            return Ok(None);
        }
        if let Some(next) = skip_known_option(words, index, grammar)? {
            index = next;
            continue;
        }
        if value.starts_with('-') {
            return Err(GuardError::Policy(format!(
                "unknown option {value} before {context}"
            )));
        }
        index += 1;
    }
    Ok(None)
}

fn consume_option_values(
    words: &[Word],
    option_index: usize,
    arity: usize,
    attached: bool,
    option: &str,
) -> Result<usize> {
    let next = option_values_end(option_index, arity, attached, option)?;
    if next > words.len() {
        return Err(GuardError::Policy(format!(
            "option {option} is missing {} value(s)",
            next - words.len()
        )));
    }
    reject_splitting_option_values(words, option_index, next, option)?;
    Ok(next)
}

fn consume_terminal_option_values(
    words: &[Word],
    option_index: usize,
    arity: usize,
    attached: bool,
    option: &str,
) -> Result<Option<usize>> {
    let next = option_values_end(option_index, arity, attached, option)?;
    if next > words.len() {
        return Ok(None);
    }
    reject_splitting_option_values(words, option_index, next, option)?;
    Ok(Some(next))
}

fn reject_splitting_option_values(
    words: &[Word],
    option_index: usize,
    next: usize,
    option: &str,
) -> Result<()> {
    if words[option_index + 1..next].iter().any(Word::may_split) {
        return Err(GuardError::Policy(format!(
            "option {option} has an unquoted dynamic value that may expand to multiple arguments"
        )));
    }
    Ok(())
}

fn option_values_end(
    option_index: usize,
    arity: usize,
    attached: bool,
    option: &str,
) -> Result<usize> {
    if attached && arity == 0 {
        return Err(GuardError::Policy(format!(
            "option {option} does not accept an attached value"
        )));
    }
    let remaining = arity.saturating_sub(usize::from(attached));
    Ok(option_index + 1 + remaining)
}

fn unknown(behavior: UnknownBehavior, reason: &str) -> Result<StageMatch> {
    match behavior {
        UnknownBehavior::Deny => Err(GuardError::Policy(reason.to_owned())),
        UnknownBehavior::Ignore => Ok(StageMatch::Stop),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::policy::{CommandGrammarStage, SelectorKind, UnknownBehavior};

    fn word(value: &str) -> Word {
        Word::synthetic(value)
    }

    fn fixture_grammar() -> CommandGrammar {
        CommandGrammar {
            executable_aliases: BTreeMap::new(),
            options: BTreeMap::from([
                ("--flag".into(), 0),
                ("--one".into(), 1),
                ("--output".into(), 1),
                ("--target".into(), 1),
                ("--two".into(), 2),
                ("-x".into(), 0),
            ]),
            terminal_options: vec!["--help".into()],
            stages: vec![
                CommandGrammarStage {
                    at: vec![],
                    selector: SelectorKind::Positional,
                    aliases: BTreeMap::from([("group".into(), "group".into())]),
                    unknown_option: UnknownBehavior::Deny,
                    unknown_selector: UnknownBehavior::Ignore,
                },
                CommandGrammarStage {
                    at: vec!["group".into()],
                    selector: SelectorKind::Positional,
                    aliases: BTreeMap::from([
                        ("mutate".into(), "mutate".into()),
                        ("read".into(), "read".into()),
                    ]),
                    unknown_option: UnknownBehavior::Deny,
                    unknown_selector: UnknownBehavior::Deny,
                },
            ],
        }
    }

    #[test]
    fn positional_stages_skip_options_by_arity() {
        let grammars = BTreeMap::from([("tool".into(), fixture_grammar())]);
        for args in [
            vec!["tool", "--flag", "group", "mutate"],
            vec!["tool", "--two", "group", "mutate", "group", "mutate"],
            vec!["tool", "group", "--one=raw", "mutate"],
            vec!["tool", "-x", "group", "--target", "tmp", "mutate"],
        ] {
            let words = args.into_iter().map(word).collect::<Vec<_>>();
            assert!(matches!(
                classify("tool", &words, &grammars).unwrap(),
                Classification::Canonical { words, .. }
                    if words == [
                        Some("tool".into()),
                        Some("group".into()),
                        Some("mutate".into()),
                    ]
            ));
        }
    }

    #[test]
    fn terminal_options_do_not_match_when_consumed_as_values() {
        let grammars = BTreeMap::from([("tool".into(), fixture_grammar())]);
        let terminal = ["tool", "group", "mutate", "--help"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert_eq!(
            classify("tool", &terminal, &grammars).unwrap(),
            Classification::Terminal
        );

        let value = ["tool", "--two", "name", "--help", "group", "read"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert!(matches!(
            classify("tool", &value, &grammars).unwrap(),
            Classification::Canonical { .. }
        ));

        let terminal_as_value = ["tool", "group", "mutate", "--output", "--help"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert!(matches!(
            classify("tool", &terminal_as_value, &grammars).unwrap(),
            Classification::Canonical { .. }
        ));
    }

    #[test]
    fn ambiguous_terminal_options_fail_closed_on_guarded_branches() {
        let grammars = BTreeMap::from([("tool".into(), fixture_grammar())]);
        let unknown_option = ["tool", "group", "mutate", "--future-output", "--help"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert!(classify("tool", &unknown_option, &grammars).is_err());

        let parsed = crate::shell::parse(r#"tool group mutate target "$OPTION" --help"#).unwrap();
        assert!(classify("tool", &parsed.commands[0].words, &grammars).is_err());
    }

    #[test]
    fn dynamic_option_selector_is_rejected() {
        let grammars = BTreeMap::from([(
            "legacy".into(),
            CommandGrammar {
                executable_aliases: BTreeMap::new(),
                options: BTreeMap::new(),
                terminal_options: vec![],
                stages: vec![CommandGrammarStage {
                    at: vec![],
                    selector: SelectorKind::Option,
                    aliases: BTreeMap::from([("--read".into(), "read".into())]),
                    unknown_option: UnknownBehavior::Deny,
                    unknown_selector: UnknownBehavior::Ignore,
                }],
            },
        )]);
        let parsed = crate::shell::parse(r#"legacy "$OPERATION" target"#).unwrap();
        assert_eq!(parsed.commands[0].words[1].static_value(), None);
        assert!(classify("legacy", &parsed.commands[0].words, &grammars).is_err());
    }

    #[test]
    fn unknown_options_only_fail_a_relevant_positional_branch() {
        let grammars = BTreeMap::from([("tool".into(), fixture_grammar())]);
        let unrelated = ["tool", "--future-option", "other"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert_eq!(
            classify("tool", &unrelated, &grammars).unwrap(),
            Classification::NotApplicable
        );

        let guarded = ["tool", "--future-option", "group", "mutate"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert!(classify("tool", &guarded, &grammars).is_err());
    }

    #[test]
    fn option_selectors_can_ignore_modifiers_but_reject_unknown_operations() {
        let grammars = BTreeMap::from([(
            "legacy".into(),
            CommandGrammar {
                executable_aliases: BTreeMap::new(),
                options: BTreeMap::new(),
                terminal_options: vec![],
                stages: vec![CommandGrammarStage {
                    at: vec![],
                    selector: SelectorKind::Option,
                    aliases: BTreeMap::from([("--read".into(), "read".into())]),
                    unknown_option: UnknownBehavior::Ignore,
                    unknown_selector: UnknownBehavior::Deny,
                }],
            },
        )]);
        let query = ["legacy", "--read", "--modifier", "path"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert!(matches!(
            classify("legacy", &query, &grammars).unwrap(),
            Classification::Canonical { .. }
        ));

        let future_operation = ["legacy", "--future-operation", "path"]
            .into_iter()
            .map(word)
            .collect::<Vec<_>>();
        assert!(classify("legacy", &future_operation, &grammars).is_err());
    }
}
