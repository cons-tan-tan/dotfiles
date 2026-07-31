use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::Path,
};

use serde::Deserialize;
use shellfirm::checks::Severity;

use crate::error::{GuardError, Result};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Policy {
    pub schema_version: u32,
    pub exact: Vec<ExactRule>,
    pub semantic: Vec<SemanticRule>,
    pub shellfirm: ShellfirmPolicy,
    pub unknown: UnknownPolicy,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExactRule {
    pub argv_prefix: Vec<String>,
    pub decision: String,
    pub reason: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SemanticRule {
    pub command_prefix: Vec<String>,
    pub option_syntax: OptionSyntax,
    pub deny: Vec<SemanticDenyRule>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OptionSyntax {
    pub value_taking: Vec<String>,
    pub optional_equals: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SemanticDenyRule {
    pub option_groups: Vec<Vec<String>>,
    pub reason: String,
    pub alternatives: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ShellfirmPolicy {
    pub enabled: bool,
    pub minimum_severity: Severity,
    pub categories: BTreeMap<String, bool>,
    pub rule_namespaces: BTreeMap<String, bool>,
    pub rules: BTreeMap<String, bool>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UnknownPolicy {
    pub parse_error: String,
    pub dynamic_executable: String,
    pub dynamic_relevant_option: String,
    pub max_decode_depth: usize,
}

impl Policy {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes = fs::read(path).map_err(|source| GuardError::ReadPolicy {
            path: path.to_path_buf(),
            source,
        })?;
        let policy: Self = serde_json::from_slice(&bytes)?;
        policy.validate_structure()?;
        Ok(policy)
    }

    pub fn validate_structure(&self) -> Result<()> {
        if self.schema_version != 1 {
            return Err(GuardError::Policy(format!(
                "unsupported schemaVersion {}",
                self.schema_version
            )));
        }
        if self.unknown.parse_error != "deny"
            || self.unknown.dynamic_executable != "deny"
            || self.unknown.dynamic_relevant_option != "deny"
        {
            return Err(GuardError::Policy(
                "unknown behavior must remain fail-closed".to_owned(),
            ));
        }
        if !(1..=32).contains(&self.unknown.max_decode_depth) {
            return Err(GuardError::Policy(
                "maxDecodeDepth must be between 1 and 32".to_owned(),
            ));
        }

        let mut prefixes = BTreeSet::new();
        for rule in &self.exact {
            validate_prefix("exact argvPrefix", &rule.argv_prefix)?;
            if rule.decision != "deny" || rule.reason.trim().is_empty() {
                return Err(GuardError::Policy(
                    "exact rules must have decision=deny and a non-empty reason".to_owned(),
                ));
            }
            if !prefixes.insert(rule.argv_prefix.clone()) {
                return Err(GuardError::Policy("duplicate exact argvPrefix".to_owned()));
            }
        }

        let mut semantic_prefixes = BTreeSet::new();
        for rule in &self.semantic {
            validate_prefix("semantic commandPrefix", &rule.command_prefix)?;
            if !semantic_prefixes.insert(rule.command_prefix.clone()) {
                return Err(GuardError::Policy(
                    "duplicate semantic commandPrefix".to_owned(),
                ));
            }
            validate_options(rule)?;
        }

        validate_selector_tokens("category", self.shellfirm.categories.keys())?;
        validate_selector_tokens("rule namespace", self.shellfirm.rule_namespaces.keys())?;
        for id in self.shellfirm.rules.keys() {
            let Some((namespace, name)) = id.split_once(':') else {
                return Err(GuardError::Policy(format!(
                    "individual Shellfirm rule has no namespace: {id}"
                )));
            };
            if namespace.is_empty() || name.is_empty() {
                return Err(GuardError::Policy(format!(
                    "individual Shellfirm rule has an invalid ID: {id}"
                )));
            }
        }
        Ok(())
    }
}

fn validate_prefix(label: &str, prefix: &[String]) -> Result<()> {
    if prefix.is_empty() || prefix.iter().any(|token| token.is_empty()) {
        return Err(GuardError::Policy(format!(
            "{label} must contain non-empty tokens"
        )));
    }
    Ok(())
}

fn validate_options(rule: &SemanticRule) -> Result<()> {
    if rule.deny.is_empty() {
        return Err(GuardError::Policy(format!(
            "semantic rule {:?} has no deny conditions",
            rule.command_prefix
        )));
    }
    let mut syntax_options = BTreeSet::new();
    for option in rule
        .option_syntax
        .value_taking
        .iter()
        .chain(&rule.option_syntax.optional_equals)
    {
        validate_option(option)?;
        if !syntax_options.insert(option) {
            return Err(GuardError::Policy(format!(
                "semantic rule {:?} repeats option syntax {option}",
                rule.command_prefix
            )));
        }
    }
    for deny in &rule.deny {
        if deny.option_groups.is_empty()
            || deny.reason.trim().is_empty()
            || deny.alternatives.is_empty()
            || deny
                .alternatives
                .iter()
                .any(|value| value.trim().is_empty())
        {
            return Err(GuardError::Policy(format!(
                "semantic rule {:?} has an incomplete deny condition",
                rule.command_prefix
            )));
        }
        let mut aliases = BTreeSet::new();
        for group in &deny.option_groups {
            if group.is_empty() {
                return Err(GuardError::Policy(format!(
                    "semantic rule {:?} has an empty option group",
                    rule.command_prefix
                )));
            }
            for option in group {
                validate_option(option)?;
                if !aliases.insert(option) {
                    return Err(GuardError::Policy(format!(
                        "semantic rule {:?} repeats option alias {option}",
                        rule.command_prefix
                    )));
                }
            }
        }
    }
    Ok(())
}

fn validate_option(option: &str) -> Result<()> {
    let valid_short = option.starts_with('-')
        && !option.starts_with("--")
        && option.chars().count() == 2
        && option
            .chars()
            .nth(1)
            .is_some_and(|value| value.is_ascii_alphanumeric());
    let valid_long = option.strip_prefix("--").is_some_and(|name| {
        !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
    });
    if valid_short || valid_long {
        Ok(())
    } else {
        Err(GuardError::Policy(format!(
            "invalid semantic command option {option}"
        )))
    }
}

fn validate_selector_tokens<'a>(
    label: &str,
    values: impl Iterator<Item = &'a String>,
) -> Result<()> {
    for value in values {
        if value.is_empty() || value.contains(':') {
            return Err(GuardError::Policy(format!(
                "invalid Shellfirm {label} selector {value:?}"
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_option_groups() {
        let json = r#"{
          "schemaVersion":1,
          "exact":[],
          "semantic":[{
            "commandPrefix":["fd"],
            "optionSyntax":{"valueTaking":[],"optionalEquals":[]},
            "deny":[{"optionGroups":[[]],"reason":"no","alternatives":["safe"]}]
          }],
          "shellfirm":{"enabled":false,"minimumSeverity":"High","categories":{},"ruleNamespaces":{},"rules":{}},
          "unknown":{"parseError":"deny","dynamicExecutable":"deny","dynamicRelevantOption":"deny","maxDecodeDepth":8}
        }"#;
        let policy: Policy = serde_json::from_str(json).unwrap();
        assert!(policy.validate_structure().is_err());
    }
}
