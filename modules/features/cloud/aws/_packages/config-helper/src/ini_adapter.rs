use std::collections::{BTreeMap, BTreeSet};

use ini_edit::ast::{AstNode, File, Section};
use ini_edit::editor::Editor;
use ini_edit::{ParseOptions, SyntaxKind, SyntaxNode, parse_with};

use crate::error::{AppError, Result};

const LOGIN_SESSION_KEY: &str = "login_session";
const REGION_KEY: &str = "region";
type CollectedSectionEntries = (
    BTreeMap<String, String>,
    BTreeMap<String, usize>,
    Vec<String>,
);

#[derive(Clone, Debug, Eq, PartialEq)]
struct SectionData {
    raw_name: String,
    values: BTreeMap<String, String>,
    entry_indices: BTreeMap<String, usize>,
    nested_entries: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Document {
    preamble: BTreeMap<String, String>,
    preamble_nested_entries: Vec<String>,
    sections: BTreeMap<String, SectionData>,
    profiles: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LoginUpdate {
    logical_profile: String,
    raw_section: String,
    login_session: String,
    added_region: Option<String>,
}

fn parse_options() -> ParseOptions {
    ParseOptions {
        inline_comments: true,
        ..ParseOptions::default()
    }
}

fn parse_document(source: &str) -> Result<Document> {
    let options = parse_options();
    let parsed = parse_with(source, &options);
    if let Some(error) = parsed.errors().first() {
        let (line, column) = error.line_col(source);
        return Err(AppError::new(format!(
            "aws-config-helper: invalid AWS config at line {line}, column {column}: {}",
            error.message
        )));
    }
    let file = File::cast(parsed.syntax())
        .ok_or_else(|| AppError::new("aws-config-helper: parser did not return an INI file"))?;
    let (preamble, preamble_nested_entries) = collect_entries(file.preamble_entries(), "preamble")?;
    let mut sections = BTreeMap::new();
    let mut profiles = BTreeMap::new();
    for section in file.sections() {
        let raw_name = section
            .name()
            .ok_or_else(|| AppError::new("aws-config-helper: section has no name"))?;
        validate_component("section name", &raw_name)?;
        if sections.contains_key(&raw_name) {
            return Err(AppError::new(format!(
                "aws-config-helper: duplicate section [{raw_name}]"
            )));
        }
        let (values, entry_indices, nested_entries) = collect_section_entries(&section, &raw_name)?;
        let data = SectionData {
            raw_name: raw_name.clone(),
            values,
            entry_indices,
            nested_entries,
        };
        if let Some(logical) = logical_profile(&raw_name)?
            && let Some(previous) = profiles.insert(logical.clone(), raw_name.clone())
        {
            return Err(AppError::new(format!(
                "aws-config-helper: sections [{previous}] and [{raw_name}] refer to the same profile {logical}"
            )));
        }
        sections.insert(raw_name, data);
    }
    Ok(Document {
        preamble,
        preamble_nested_entries,
        sections,
        profiles,
    })
}

pub fn validate(source: &str) -> Result<()> {
    parse_document(source).map(|_| ())
}

fn collect_entries(
    entries: impl Iterator<Item = ini_edit::ast::Entry>,
    location: &str,
) -> Result<(BTreeMap<String, String>, Vec<String>)> {
    let mut values = BTreeMap::new();
    let mut nested_entries = Vec::new();
    for entry in entries {
        if is_indented(&entry) {
            nested_entries.push(entry.syntax().text().to_string());
            continue;
        }
        let key = entry.key().ok_or_else(|| {
            AppError::new(format!("aws-config-helper: missing key in {location}"))
        })?;
        let normalized = normalize_key(&key)?;
        let value = entry.value().ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: key {key} in {location} has no value"
            ))
        })?;
        if values.insert(normalized, value).is_some() {
            return Err(AppError::new(format!(
                "aws-config-helper: duplicate top-level key {key} in {location}"
            )));
        }
    }
    Ok((values, nested_entries))
}

fn collect_section_entries(section: &Section, raw_name: &str) -> Result<CollectedSectionEntries> {
    let mut values = BTreeMap::new();
    let mut entry_indices = BTreeMap::new();
    let mut nested_entries = Vec::new();
    for (index, entry) in section.entries().enumerate() {
        if is_indented(&entry) {
            nested_entries.push(entry.syntax().text().to_string());
            continue;
        }
        let key = entry.key().ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: missing key in section [{raw_name}]"
            ))
        })?;
        let normalized = normalize_key(&key)?;
        let value = entry.value().ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: key {key} in section [{raw_name}] has no value"
            ))
        })?;
        if values.insert(normalized.clone(), value).is_some() {
            return Err(AppError::new(format!(
                "aws-config-helper: duplicate top-level key {key} in section [{raw_name}]"
            )));
        }
        entry_indices.insert(normalized, index);
    }
    Ok((values, entry_indices, nested_entries))
}

fn is_indented(entry: &ini_edit::ast::Entry) -> bool {
    entry
        .syntax()
        .first_token()
        .is_some_and(|token| token.kind() == SyntaxKind::WHITESPACE)
}

fn normalize_key(key: &str) -> Result<String> {
    validate_component("key", key)?;
    Ok(key.to_ascii_lowercase())
}

fn validate_component(kind: &str, value: &str) -> Result<()> {
    if value.is_empty()
        || value.contains(['\r', '\n', '\0'])
        || (kind == "section name" && value.contains(['[', ']']))
    {
        return Err(AppError::new(format!("aws-config-helper: invalid {kind}")));
    }
    Ok(())
}

fn logical_profile(raw_name: &str) -> Result<Option<String>> {
    if raw_name == "default" {
        return Ok(Some("default".to_string()));
    }
    let Some(rest) = raw_name.strip_prefix("profile ") else {
        return Ok(None);
    };
    let logical = if rest.starts_with('"') || rest.ends_with('"') {
        let Some(inner) = rest
            .strip_prefix('"')
            .and_then(|value| value.strip_suffix('"'))
        else {
            return Err(AppError::new(format!(
                "aws-config-helper: malformed quoted profile section [{raw_name}]"
            )));
        };
        if inner.contains('"') {
            return Err(AppError::new(format!(
                "aws-config-helper: malformed quoted profile section [{raw_name}]"
            )));
        }
        inner
    } else {
        rest
    };
    if logical.is_empty() {
        return Err(AppError::new(format!(
            "aws-config-helper: empty profile name in section [{raw_name}]"
        )));
    }
    validate_component("profile name", logical)?;
    Ok(Some(logical.to_string()))
}

fn profile<'a>(document: &'a Document, logical: &str) -> Option<&'a SectionData> {
    let raw = document.profiles.get(logical)?;
    document.sections.get(raw)
}

pub fn validate_login_candidate(baseline: &str, candidate: &str) -> Result<LoginUpdate> {
    let baseline = parse_document(baseline)?;
    let candidate = parse_document(candidate)?;
    if baseline.preamble != candidate.preamble
        || baseline.preamble_nested_entries != candidate.preamble_nested_entries
    {
        return Err(AppError::new(
            "aws-config-helper: aws login changed preamble settings",
        ));
    }

    let profile_sections = baseline
        .profiles
        .values()
        .chain(candidate.profiles.values())
        .cloned()
        .collect::<BTreeSet<_>>();
    let section_names = baseline
        .sections
        .keys()
        .chain(candidate.sections.keys())
        .cloned()
        .collect::<BTreeSet<_>>();
    for raw_name in section_names.difference(&profile_sections) {
        if baseline.sections.get(raw_name) != candidate.sections.get(raw_name) {
            return Err(AppError::new(format!(
                "aws-config-helper: aws login changed non-profile section [{raw_name}]"
            )));
        }
    }

    let logical_profiles = baseline
        .profiles
        .keys()
        .chain(candidate.profiles.keys())
        .cloned()
        .collect::<BTreeSet<_>>();
    let mut update = None;
    for logical in logical_profiles {
        let before = profile(&baseline, &logical);
        let Some(after) = profile(&candidate, &logical) else {
            return Err(AppError::new(format!(
                "aws-config-helper: aws login removed profile {logical}"
            )));
        };
        if let Some(before) = before
            && before.raw_name != after.raw_name
        {
            return Err(AppError::new(format!(
                "aws-config-helper: aws login renamed profile {logical}"
            )));
        }
        let before_nested = before.map_or(&[][..], |section| section.nested_entries.as_slice());
        if before_nested != after.nested_entries {
            return Err(AppError::new(format!(
                "aws-config-helper: aws login changed nested settings in profile {logical}"
            )));
        }
        let empty = BTreeMap::new();
        let before_values = before.map_or(&empty, |section| &section.values);
        let keys = before_values
            .keys()
            .chain(after.values.keys())
            .cloned()
            .collect::<BTreeSet<_>>();
        let mut session_change = None;
        let mut added_region = None;
        let mut changed = false;
        for key in keys {
            let old = before_values.get(&key);
            let new = after.values.get(&key);
            if old == new {
                continue;
            }
            changed = true;
            match key.as_str() {
                LOGIN_SESSION_KEY => {
                    let Some(value) = new else {
                        return Err(AppError::new(format!(
                            "aws-config-helper: aws login removed {LOGIN_SESSION_KEY} from profile {logical}"
                        )));
                    };
                    if value.trim().is_empty() {
                        return Err(AppError::new(format!(
                            "aws-config-helper: aws login produced an empty {LOGIN_SESSION_KEY} for profile {logical}"
                        )));
                    }
                    session_change = Some(value.clone());
                }
                REGION_KEY if old.is_none() => {
                    let Some(value) = new else {
                        return Err(AppError::new(format!(
                            "aws-config-helper: aws login removed {REGION_KEY} from profile {logical}"
                        )));
                    };
                    if value.trim().is_empty() {
                        return Err(AppError::new(format!(
                            "aws-config-helper: aws login produced an empty {REGION_KEY} for profile {logical}"
                        )));
                    }
                    added_region = Some(value.clone());
                }
                _ => {
                    return Err(AppError::new(format!(
                        "aws-config-helper: aws login changed disallowed key {key} in profile {logical}"
                    )));
                }
            }
        }
        if before.is_none() && !changed {
            return Err(AppError::new(format!(
                "aws-config-helper: aws login added empty profile {logical}"
            )));
        }
        if changed {
            let Some(login_session) = session_change else {
                return Err(AppError::new(format!(
                    "aws-config-helper: aws login changed profile {logical} without changing {LOGIN_SESSION_KEY}"
                )));
            };
            if update.is_some() {
                return Err(AppError::new(
                    "aws-config-helper: aws login changed more than one profile",
                ));
            }
            update = Some(LoginUpdate {
                logical_profile: logical,
                raw_section: after.raw_name.clone(),
                login_session,
                added_region,
            });
        }
    }
    update.ok_or_else(|| {
        AppError::new(format!(
            "aws-config-helper: aws login did not change {LOGIN_SESSION_KEY}"
        ))
    })
}

pub fn apply_login_update(target: &str, update: &LoginUpdate) -> Result<String> {
    let document = parse_document(target)?;
    let raw_section = profile(&document, &update.logical_profile)
        .map_or(update.raw_section.as_str(), |section| {
            section.raw_name.as_str()
        });
    let mut output = set_profile_value(
        target,
        &update.logical_profile,
        raw_section,
        LOGIN_SESSION_KEY,
        &update.login_session,
    )?;
    if let Some(region) = &update.added_region {
        let refreshed = parse_document(&output)?;
        let has_region = profile(&refreshed, &update.logical_profile)
            .is_some_and(|section| section.values.contains_key(REGION_KEY));
        if !has_region {
            output = set_profile_value(
                &output,
                &update.logical_profile,
                raw_section,
                REGION_KEY,
                region,
            )?;
        }
    }
    Ok(output)
}

pub fn reconcile(baseline: &str, current: &str, managed_sections: &[String]) -> Result<String> {
    let baseline_document = parse_document(baseline)?;
    let current_document = parse_document(current)?;
    let mut logical_profiles = BTreeSet::new();
    for raw_section in managed_sections {
        validate_component("managed section name", raw_section)?;
        let logical = logical_profile(raw_section)?.ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: managed section [{raw_section}] is not an AWS profile"
            ))
        })?;
        let Some(baseline_section) = profile(&baseline_document, &logical) else {
            return Err(AppError::new(format!(
                "aws-config-helper: managed profile {logical} is absent from the baseline"
            )));
        };
        if baseline_section.raw_name != *raw_section {
            return Err(AppError::new(format!(
                "aws-config-helper: managed section [{raw_section}] does not match the baseline"
            )));
        }
        if !logical_profiles.insert(logical.clone()) {
            return Err(AppError::new(format!(
                "aws-config-helper: duplicate managed profile {logical}"
            )));
        }
    }

    let mut output = baseline.to_string();
    for logical in logical_profiles {
        let Some(current_profile) = profile(&current_document, &logical) else {
            continue;
        };
        let Some(session) = current_profile.values.get(LOGIN_SESSION_KEY) else {
            continue;
        };
        if session.is_empty() {
            continue;
        }
        let baseline_profile = profile(&baseline_document, &logical)
            .expect("managed profile was checked against the baseline");
        output = set_profile_value(
            &output,
            &logical,
            &baseline_profile.raw_name,
            LOGIN_SESSION_KEY,
            session,
        )?;
    }
    Ok(output)
}

fn set_profile_value(
    source: &str,
    logical: &str,
    raw_section: &str,
    key: &str,
    value: &str,
) -> Result<String> {
    validate_component("section name", raw_section)?;
    validate_component("key", key)?;
    validate_component("value", value)?;
    let document = parse_document(source)?;
    if let Some(section) = profile(&document, logical) {
        if let Some(index) = section.entry_indices.get(&key.to_ascii_lowercase()) {
            if section.values.get(&key.to_ascii_lowercase()) == Some(&value.to_string()) {
                return Ok(source.to_string());
            }
            let options = parse_options();
            let editor = Editor::with_parse_options(source, &options);
            let entries = editor.section(&section.raw_name).entries_mut();
            let entry = entries.get(*index).ok_or_else(|| {
                AppError::new(format!(
                    "aws-config-helper: entry position changed in section [{}]",
                    section.raw_name
                ))
            })?;
            entry.set_value(value);
            let output = editor.finish();
            verify_value(&output, logical, key, value)?;
            return Ok(output);
        }
        return insert_entry(source, &section.raw_name, logical, key, value);
    }
    append_section(source, raw_section, logical, key, value)
}

fn verify_value(source: &str, logical: &str, key: &str, value: &str) -> Result<()> {
    let document = parse_document(source)?;
    let actual = profile(&document, logical)
        .and_then(|section| section.values.get(&key.to_ascii_lowercase()));
    if actual != Some(&value.to_string()) {
        return Err(AppError::new(
            "aws-config-helper: edited value did not round-trip through the INI parser",
        ));
    }
    Ok(())
}

fn insert_entry(
    source: &str,
    raw_section: &str,
    logical: &str,
    key: &str,
    value: &str,
) -> Result<String> {
    let parsed = parse_with(source, &parse_options());
    let root = parsed.syntax();
    let file = File::cast(root.clone())
        .ok_or_else(|| AppError::new("aws-config-helper: parser did not return an INI file"))?;
    let section = file
        .sections()
        .find(|section| section.name().as_deref() == Some(raw_section))
        .ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: section [{raw_section}] disappeared before insertion"
            ))
        })?;
    let content = section
        .syntax()
        .children()
        .filter(|node| {
            matches!(
                node.kind(),
                SyntaxKind::SECTION_HEADER | SyntaxKind::ENTRY | SyntaxKind::COMMENT_LINE
            )
        })
        .last()
        .ok_or_else(|| {
            AppError::new(format!(
                "aws-config-helper: section [{raw_section}] has no header"
            ))
        })?;
    let offset = u32::from(content.text_range().end()) as usize;
    let needs_newline = content
        .last_token()
        .is_none_or(|token| token.kind() != SyntaxKind::NEWLINE);
    let eol = preferred_eol(section.syntax(), &root);
    let mut insertion = String::new();
    if needs_newline {
        insertion.push_str(eol);
    }
    insertion.push_str(key);
    insertion.push_str(" = ");
    insertion.push_str(value);
    insertion.push_str(eol);
    let mut output = source.to_string();
    output.insert_str(offset, &insertion);
    verify_value(&output, logical, key, value)?;
    Ok(output)
}

fn append_section(
    source: &str,
    raw_section: &str,
    logical: &str,
    key: &str,
    value: &str,
) -> Result<String> {
    if logical_profile(raw_section)?.as_deref() != Some(logical) {
        return Err(AppError::new(format!(
            "aws-config-helper: section [{raw_section}] does not identify profile {logical}"
        )));
    }
    let parsed = parse_with(source, &parse_options());
    let root = parsed.syntax();
    let eol = preferred_eol(&root, &root);
    let separator = section_separator(&root, source, eol);
    let mut output = source.to_string();
    output.push_str(&separator);
    output.push('[');
    output.push_str(raw_section);
    output.push(']');
    output.push_str(eol);
    output.push_str(key);
    output.push_str(" = ");
    output.push_str(value);
    output.push_str(eol);
    verify_value(&output, logical, key, value)?;
    Ok(output)
}

fn preferred_eol(primary: &SyntaxNode, fallback: &SyntaxNode) -> &'static str {
    let newline = primary
        .descendants_with_tokens()
        .filter_map(|element| element.into_token())
        .find(|token| token.kind() == SyntaxKind::NEWLINE)
        .or_else(|| {
            fallback
                .descendants_with_tokens()
                .filter_map(|element| element.into_token())
                .find(|token| token.kind() == SyntaxKind::NEWLINE)
        });
    match newline.as_ref().map(|token| token.text()) {
        Some("\r\n") => "\r\n",
        Some("\r") => "\r",
        _ => "\n",
    }
}

fn section_separator(root: &SyntaxNode, source: &str, eol: &str) -> String {
    if source.is_empty() {
        return String::new();
    }
    let last_line = match root.last_child() {
        Some(node) if node.kind() == SyntaxKind::SECTION => node.last_child(),
        other => other,
    };
    let terminated = root
        .last_token()
        .is_some_and(|token| token.kind() == SyntaxKind::NEWLINE);
    let blank = last_line.is_some_and(|node| node.kind() == SyntaxKind::BLANK_LINE);
    match (blank, terminated) {
        (true, true) => String::new(),
        (true, false) | (false, true) => eol.to_string(),
        (false, false) => format!("{eol}{eol}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unchanged_documents_round_trip_all_newline_styles() {
        for source in [
            "[profile test]\nregion = one\n",
            "[profile test]\r\nregion = one\r\n",
            "[profile test]\rregion = one\r",
            "[profile test]\nregion = one",
        ] {
            let document = parse_document(source).unwrap();
            assert_eq!(
                profile(&document, "test").unwrap().values.get("region"),
                Some(&"one".to_string())
            );
            assert_eq!(
                set_profile_value(source, "test", "profile test", "region", "one").unwrap(),
                source
            );
        }
    }

    #[test]
    fn existing_value_preserves_formatting_and_nested_keys() {
        let source = concat!(
            "[profile \"with space\"]\r\n",
            "region: old   ; keep\r\n",
            "s3 =\r\n",
            "  login_session = nested\r\n",
            "login_session = old-session # note\r\n",
        );
        let update = LoginUpdate {
            logical_profile: "with space".to_string(),
            raw_section: "profile \"with space\"".to_string(),
            login_session: "new-session".to_string(),
            added_region: None,
        };

        let output = apply_login_update(source, &update).unwrap();

        assert!(output.contains("  login_session = nested\r\n"));
        assert!(output.contains("login_session = new-session # note\r\n"));
        assert!(output.contains("region: old   ; keep\r\n"));
    }

    #[test]
    fn insertion_uses_the_section_newline_and_keeps_existing_bytes() {
        for (eol, terminated) in [("\n", true), ("\r\n", true), ("\r", true), ("\r\n", false)] {
            let source = if terminated {
                format!("[profile test]{eol}region = one{eol}")
            } else {
                format!("[profile test]{eol}region = one")
            };
            let output = set_profile_value(
                &source,
                "test",
                "profile test",
                LOGIN_SESSION_KEY,
                "session",
            )
            .unwrap();
            assert!(output.starts_with(&source));
            assert!(output.ends_with(&format!("{eol}login_session = session{eol}")));
        }
    }

    #[test]
    fn missing_section_uses_the_file_newline_and_a_single_blank_line() {
        for eol in ["\n", "\r\n", "\r"] {
            let source = format!("[profile first]{eol}region = one{eol}");
            let output = set_profile_value(
                &source,
                "second",
                "profile second",
                LOGIN_SESSION_KEY,
                "session",
            )
            .unwrap();
            assert_eq!(
                output,
                format!(
                    "[profile first]{eol}region = one{eol}{eol}[profile second]{eol}login_session = session{eol}"
                )
            );
        }
    }

    #[test]
    fn duplicate_and_malformed_input_is_rejected_without_values_in_errors() {
        for source in [
            "[profile test]\nkey = secret\nkey = secret\n",
            "[profile test]\ninvalid\n",
            "[profile test]\nregion = one\n[profile \"test\"]\nregion = two\n",
        ] {
            let error = parse_document(source).unwrap_err().to_string();
            assert!(!error.contains("secret"));
        }
    }

    #[test]
    fn bom_and_inline_comment_are_preserved() {
        let source = "\u{FEFF}[profile test]\nregion = one ; keep\n";
        let output = set_profile_value(source, "test", "profile test", "region", "two").unwrap();
        assert_eq!(output, "\u{FEFF}[profile test]\nregion = two ; keep\n");
    }

    #[test]
    fn candidate_allows_only_one_session_and_prompted_region() {
        let baseline = "[profile test]\noutput = json\n";
        let candidate =
            "[profile test]\noutput = json\nregion = ap-northeast-1\nlogin_session = token\n";
        let update = validate_login_candidate(baseline, candidate).unwrap();
        assert_eq!(update.logical_profile, "test");
        assert_eq!(update.added_region.as_deref(), Some("ap-northeast-1"));

        let target = "[profile test]\ncredential_process = command\nregion = keep\n# comment\n";
        let output = apply_login_update(target, &update).unwrap();
        assert!(output.contains("credential_process = command"));
        assert!(output.contains("region = keep"));
        assert!(output.contains("login_session = token"));
    }

    #[test]
    fn candidate_rejects_other_changes_multiple_profiles_and_session_removal() {
        let baseline =
            "[profile one]\noutput = json\nlogin_session = old\n\n[profile two]\noutput = json\n";
        for candidate in [
            "[profile one]\noutput = yaml\nlogin_session = new\n\n[profile two]\noutput = json\n",
            "[profile one]\noutput = json\nlogin_session = new\n\n[profile two]\noutput = json\nlogin_session = other\n",
            "[profile one]\noutput = json\n\n[profile two]\noutput = json\n",
        ] {
            assert!(validate_login_candidate(baseline, candidate).is_err());
        }
    }

    #[test]
    fn candidate_rejects_nested_and_preamble_changes() {
        let baseline = concat!(
            "global = keep\n",
            "[profile test]\n",
            "services =\n",
            "  endpoint = old\n",
        );
        for candidate in [
            concat!(
                "global = changed\n",
                "[profile test]\n",
                "services =\n",
                "  endpoint = old\n",
                "login_session = token\n",
            ),
            concat!(
                "global = keep\n",
                "[profile test]\n",
                "services =\n",
                "  endpoint = new\n",
                "login_session = token\n",
            ),
        ] {
            assert!(validate_login_candidate(baseline, candidate).is_err());
        }
    }

    #[test]
    fn candidate_rejects_empty_region_and_empty_extra_profile() {
        let baseline = "[profile test]\noutput = json\n";
        for candidate in [
            concat!(
                "[profile test]\n",
                "output = json\n",
                "login_session =   \n",
            ),
            concat!(
                "[profile test]\n",
                "output = json\n",
                "region =   \n",
                "login_session = token\n",
            ),
            concat!(
                "[profile test]\n",
                "output = json\n",
                "login_session = token\n",
                "\n",
                "[profile extra]\n",
            ),
        ] {
            assert!(validate_login_candidate(baseline, candidate).is_err());
        }
    }

    #[test]
    fn reconcile_keeps_managed_sessions_and_removes_undeclared_profiles() {
        let baseline = "[profile managed]\nregion = one\ncredential_process = command\n";
        let current = concat!(
            "[profile managed]\n",
            "region = changed\n",
            "login_session = session\n",
            "\n",
            "[profile unknown]\n",
            "login_session = remove\n",
        );

        let output = reconcile(baseline, current, &["profile managed".to_string()]).unwrap();

        assert!(output.contains("region = one"));
        assert!(output.contains("credential_process = command"));
        assert!(output.contains("login_session = session"));
        assert!(!output.contains("unknown"));
        assert!(!output.contains("changed"));
    }
}
