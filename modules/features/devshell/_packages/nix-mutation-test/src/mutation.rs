use std::collections::BTreeSet;

use rnix::SyntaxKind;
use rnix::ast::{self, BinOpKind, HasEntry};
use rowan::ast::AstNode;
use sha2::{Digest, Sha256};

use crate::model::{Candidate, MutationKind, Offsets, OperatorGroup, Position, Range};

const IGNORE_MARKER: &str = "nix-mutation-test: ignore";

pub fn discover(
    file: &str,
    source: &str,
    selected: &BTreeSet<OperatorGroup>,
) -> Result<Vec<Candidate>, String> {
    let parse = rnix::Root::parse(source);
    if let Some(error) = parse.errors().first() {
        return Err(format!("rnix could not parse {file}: {error}"));
    }

    let syntax = parse.syntax();
    let source_hash = hash(source.as_bytes());
    let ignored_lines = ignored_marker_lines(&syntax, source);
    let mut candidates = Vec::new();

    if group_selected(selected, OperatorGroup::Boolean) {
        for node in syntax.descendants().filter_map(ast::Ident::cast) {
            if !is_expression_identifier(&node) {
                continue;
            }
            let Some(token) = node.ident_token() else {
                continue;
            };
            if !is_unshadowed_boolean(&node, token.text()) {
                continue;
            }
            let (kind, replacement) = match token.text() {
                "true" => (MutationKind::BooleanTrue, "false"),
                "false" => (MutationKind::BooleanFalse, "true"),
                _ => continue,
            };
            push_candidate(
                &mut candidates,
                file,
                source,
                &source_hash,
                &ignored_lines,
                kind,
                token.text(),
                replacement,
                token.text_range(),
            );
        }
    }

    for node in syntax.descendants().filter_map(ast::BinOp::cast) {
        let Some(operator) = node.operator() else {
            continue;
        };
        let (kind, token_kind, replacement) = match operator {
            BinOpKind::And => (MutationKind::LogicalAnd, SyntaxKind::TOKEN_AND_AND, "||"),
            BinOpKind::Or => (MutationKind::LogicalOr, SyntaxKind::TOKEN_OR_OR, "&&"),
            BinOpKind::Equal => (MutationKind::EqualityEqual, SyntaxKind::TOKEN_EQUAL, "!="),
            BinOpKind::NotEqual => (
                MutationKind::EqualityNotEqual,
                SyntaxKind::TOKEN_NOT_EQUAL,
                "==",
            ),
            _ => continue,
        };
        if !group_selected(selected, kind.group()) {
            continue;
        }
        let Some(token) = node
            .syntax()
            .children_with_tokens()
            .filter_map(|element| element.into_token())
            .find(|token| token.kind() == token_kind)
        else {
            continue;
        };
        push_candidate(
            &mut candidates,
            file,
            source,
            &source_hash,
            &ignored_lines,
            kind,
            token.text(),
            replacement,
            token.text_range(),
        );
    }

    candidates.sort_by(|left, right| {
        (
            &left.file,
            left.replacement_offsets.start,
            left.replacement_offsets.end,
            &left.mutation,
        )
            .cmp(&(
                &right.file,
                right.replacement_offsets.start,
                right.replacement_offsets.end,
                &right.mutation,
            ))
    });
    Ok(candidates)
}

pub fn apply(source: &str, candidate: &Candidate) -> Result<String, String> {
    let start = candidate.replacement_offsets.start;
    let end = candidate.replacement_offsets.end;
    let Some(original) = source.get(start..end) else {
        return Err(format!("{} has invalid byte offsets", candidate.id));
    };
    if original != candidate.text {
        return Err(format!(
            "{} source changed: expected {:?}, found {:?}",
            candidate.id, candidate.text, original
        ));
    }

    let mut mutated =
        String::with_capacity(source.len() - original.len() + candidate.replacement.len());
    mutated.push_str(&source[..start]);
    mutated.push_str(&candidate.replacement);
    mutated.push_str(&source[end..]);
    Ok(mutated)
}

fn group_selected(selected: &BTreeSet<OperatorGroup>, group: OperatorGroup) -> bool {
    selected.is_empty() || selected.contains(&group)
}

fn is_expression_identifier(identifier: &ast::Ident) -> bool {
    let Some(parent) = identifier.syntax().parent() else {
        return true;
    };
    match parent.kind() {
        // Pattern names and their default expressions share NODE_IDENT. Use
        // the typed child accessor so `{ enabled ? false }` keeps its mutant.
        SyntaxKind::NODE_PAT_ENTRY => ast::PatEntry::cast(parent)
            .and_then(|entry| entry.default())
            .is_some_and(|default| default.syntax() == identifier.syntax()),
        SyntaxKind::NODE_ATTRPATH
        | SyntaxKind::NODE_IDENT_PARAM
        | SyntaxKind::NODE_INHERIT
        | SyntaxKind::NODE_PAT_BIND => false,
        _ => true,
    }
}

fn is_unshadowed_boolean(identifier: &ast::Ident, name: &str) -> bool {
    let identifier_range = identifier.syntax().text_range();
    for ancestor in identifier.syntax().ancestors().skip(1) {
        match ancestor.kind() {
            SyntaxKind::NODE_LAMBDA => {
                let lambda = ast::Lambda::cast(ancestor).expect("kind checked");
                if lambda.param().is_some_and(|param| param_binds(param, name)) {
                    return false;
                }
            }
            SyntaxKind::NODE_LET_IN => {
                let let_in = ast::LetIn::cast(ancestor).expect("kind checked");
                if entries_bind(&let_in, name) {
                    return false;
                }
            }
            SyntaxKind::NODE_LEGACY_LET => {
                let legacy = ast::LegacyLet::cast(ancestor).expect("kind checked");
                if entries_bind(&legacy, name) {
                    return false;
                }
            }
            SyntaxKind::NODE_ATTR_SET => {
                let attr_set = ast::AttrSet::cast(ancestor).expect("kind checked");
                if attr_set.rec_token().is_some() && entries_bind(&attr_set, name) {
                    return false;
                }
            }
            SyntaxKind::NODE_WITH => {
                let with_expr = ast::With::cast(ancestor).expect("kind checked");
                if with_expr.body().is_some_and(|body| {
                    let body_range = body.syntax().text_range();
                    body_range.start() <= identifier_range.start()
                        && identifier_range.end() <= body_range.end()
                }) {
                    // A with namespace is dynamic, so the built-in binding
                    // cannot be proven without evaluation.
                    return false;
                }
            }
            _ => {}
        }
    }
    true
}

fn param_binds(param: ast::Param, name: &str) -> bool {
    match param {
        ast::Param::IdentParam(parameter) => parameter
            .ident()
            .is_some_and(|identifier| ident_is(&identifier, name)),
        ast::Param::Pattern(pattern) => {
            pattern.pat_entries().any(|entry| {
                entry
                    .ident()
                    .is_some_and(|identifier| ident_is(&identifier, name))
            }) || pattern
                .pat_bind()
                .and_then(|binding| binding.ident())
                .is_some_and(|identifier| ident_is(&identifier, name))
        }
    }
}

fn entries_bind(entries: &impl HasEntry, name: &str) -> bool {
    entries.attrpath_values().any(|entry| {
        entry
            .attrpath()
            .and_then(|path| path.attrs().next())
            .is_some_and(|attribute| attr_may_bind(attribute, name))
    }) || entries
        .inherits()
        .flat_map(|inherit| inherit.attrs())
        .any(|attribute| attr_may_bind(attribute, name))
}

fn attr_may_bind(attribute: ast::Attr, name: &str) -> bool {
    match attribute {
        ast::Attr::Ident(identifier) => ident_is(&identifier, name),
        ast::Attr::Str(string) => {
            let text = string.to_string();
            text == format!("\"{name}\"") || text.contains("${") || text.contains('\\')
        }
        ast::Attr::Dynamic(_) => true,
    }
}

fn ident_is(identifier: &ast::Ident, name: &str) -> bool {
    identifier
        .ident_token()
        .is_some_and(|token| token.text() == name)
}

fn ignored_marker_lines(syntax: &rnix::SyntaxNode, source: &str) -> BTreeSet<usize> {
    syntax
        .descendants_with_tokens()
        .filter_map(|element| element.into_token())
        .filter(|token| token.kind() == SyntaxKind::TOKEN_COMMENT)
        .flat_map(|token| {
            let token_start = usize::from(token.text_range().start());
            token
                .text()
                .match_indices(IGNORE_MARKER)
                .map(move |(offset, _)| line_number_at(source, token_start + offset))
                .collect::<Vec<_>>()
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn push_candidate(
    candidates: &mut Vec<Candidate>,
    file: &str,
    source: &str,
    source_hash: &str,
    ignored_lines: &BTreeSet<usize>,
    kind: MutationKind,
    text: &str,
    replacement: &str,
    text_range: rnix::TextRange,
) {
    let start = usize::from(text_range.start());
    let end = usize::from(text_range.end());
    if ignored_lines.contains(&line_number_at(source, start)) {
        return;
    }
    let mutation = kind.name();
    let id_material = format!("{file}\0{mutation}\0{start}\0{end}\0{source_hash}");
    candidates.push(Candidate {
        id: hash(id_material.as_bytes())[..16].to_owned(),
        file: file.to_owned(),
        mutation: mutation.to_owned(),
        operator: kind.group(),
        text: text.to_owned(),
        replacement: replacement.to_owned(),
        range: Range {
            start: position_at(source, start),
            end: position_at(source, end),
        },
        replacement_offsets: Offsets { start, end },
        source_hash: source_hash.to_owned(),
    });
}

fn line_number_at(source: &str, offset: usize) -> usize {
    source[..offset]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
}

fn position_at(source: &str, offset: usize) -> Position {
    let prefix = &source[..offset];
    Position {
        line: line_number_at(source, offset),
        column: prefix
            .rsplit_once('\n')
            .map_or(prefix, |(_, line)| line)
            .chars()
            .count(),
    }
}

fn hash(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn groups(groups: &[OperatorGroup]) -> BTreeSet<OperatorGroup> {
        groups.iter().copied().collect()
    }

    #[test]
    fn boolean_candidates_exclude_strings_comments_and_attribute_names() {
        let source = r#"{ true = "true"; inherit false; value = true; # false
other = false; }"#;
        let candidates =
            discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
        assert_eq!(
            candidates
                .iter()
                .map(|candidate| candidate.mutation.as_str())
                .collect::<Vec<_>>(),
            ["boolean-true", "boolean-false"]
        );
    }

    #[test]
    fn operators_replace_only_the_operator_token() {
        let source = "(true  &&\n false) == false";
        let candidates = discover("target.nix", source, &BTreeSet::new()).unwrap();
        let logical = candidates
            .iter()
            .find(|candidate| candidate.mutation == "logical-and")
            .unwrap();
        assert_eq!(logical.text, "&&");
        assert_eq!(
            apply(source, logical).unwrap(),
            "(true  ||\n false) == false"
        );
    }

    #[test]
    fn inline_ignore_marker_suppresses_only_that_line() {
        let source = "{ ignored = true; # nix-mutation-test: ignore\nobserved = false; }";
        let candidates =
            discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].mutation, "boolean-false");
    }

    #[test]
    fn ignore_marker_must_be_inside_a_comment() {
        let source = r#"{ note = "nix-mutation-test: ignore"; observed = true; }"#;
        let candidates =
            discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].mutation, "boolean-true");
    }

    #[test]
    fn identifiers_inside_interpolation_remain_expressions() {
        let source = r#""${if true then "yes" else "false"}""#;
        let candidates =
            discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].text, "true");
    }

    #[test]
    fn pattern_defaults_are_expressions_but_bound_names_are_not_booleans() {
        let source = "{ true ? false, enabled ? true }: true";
        let candidates =
            discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
        assert_eq!(
            candidates
                .iter()
                .map(|candidate| candidate.mutation.as_str())
                .collect::<Vec<_>>(),
            ["boolean-false"]
        );
    }

    #[test]
    fn shadowed_boolean_names_are_excluded_conservatively() {
        for source in [
            "let true = 7; in true",
            "true: true",
            "rec { true = 4; value = true; }",
            "with namespace; true",
        ] {
            let candidates =
                discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
            assert!(candidates.is_empty(), "unexpected candidate in {source}");
        }
    }

    #[test]
    fn unrelated_bindings_do_not_hide_booleans() {
        let source = "let answer = true; in { inherit answer; value = false; }";
        let candidates =
            discover("target.nix", source, &groups(&[OperatorGroup::Boolean])).unwrap();
        assert_eq!(
            candidates
                .iter()
                .map(|candidate| candidate.mutation.as_str())
                .collect::<Vec<_>>(),
            ["boolean-true", "boolean-false"]
        );
    }

    #[test]
    fn ids_are_deterministic_and_source_sensitive() {
        let first = discover("target.nix", "true", &BTreeSet::new()).unwrap();
        let same = discover("target.nix", "true", &BTreeSet::new()).unwrap();
        let changed = discover("target.nix", " true", &BTreeSet::new()).unwrap();
        assert_eq!(first[0].id, same[0].id);
        assert_ne!(first[0].id, changed[0].id);
    }
}
