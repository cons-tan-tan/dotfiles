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
    #[serde(default)]
    pub command_grammars: BTreeMap<String, CommandGrammar>,
    pub exact: Vec<ExactRule>,
    pub semantic: Vec<SemanticRule>,
    #[serde(default)]
    pub shell: ShellPolicy,
    pub shellfirm: ShellfirmPolicy,
    pub unknown: UnknownPolicy,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CommandGrammar {
    #[serde(default)]
    pub executable_aliases: BTreeMap<String, String>,
    pub options: BTreeMap<String, usize>,
    pub terminal_options: Vec<String>,
    pub stages: Vec<CommandGrammarStage>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CommandGrammarStage {
    pub at: Vec<String>,
    pub selector: SelectorKind,
    pub aliases: BTreeMap<String, String>,
    pub unknown_option: UnknownBehavior,
    pub unknown_selector: UnknownBehavior,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SelectorKind {
    Option,
    Positional,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum UnknownBehavior {
    Deny,
    Ignore,
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
    pub guidance: Option<String>,
    pub option_syntax: OptionSyntax,
    pub deny: Vec<SemanticDenyRule>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ShellPolicy {
    #[serde(default)]
    pub redirection: RedirectionPolicy,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RedirectionPolicy {
    #[serde(default = "default_true")]
    pub empty_file: bool,
}

impl Default for RedirectionPolicy {
    fn default() -> Self {
        Self { empty_file: true }
    }
}

const fn default_true() -> bool {
    true
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
        if self.schema_version != 3 {
            return Err(GuardError::Policy(format!(
                "unsupported schemaVersion {}",
                self.schema_version
            )));
        }

        validate_command_grammars(&self.command_grammars)?;
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
            if rule
                .guidance
                .as_deref()
                .is_some_and(|guidance| guidance.trim().is_empty())
            {
                return Err(GuardError::Policy(format!(
                    "semantic rule {:?} has empty guidance",
                    rule.command_prefix
                )));
            }
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

fn validate_command_grammars(grammars: &BTreeMap<String, CommandGrammar>) -> Result<()> {
    for (executable, grammar) in grammars {
        if executable.is_empty()
            || !executable
                .chars()
                .all(|value| value.is_ascii_alphanumeric() || "_+@%.-".contains(value))
            || !executable
                .chars()
                .next()
                .is_some_and(|value| value.is_ascii_alphanumeric() || value == '_')
        {
            return Err(GuardError::Policy(format!(
                "invalid command grammar executable {executable:?}"
            )));
        }
        if !grammar.stages.is_empty() && !grammar.stages.iter().any(|stage| stage.at.is_empty()) {
            return Err(GuardError::Policy(format!(
                "command grammar {executable:?} must define a root selector stage"
            )));
        }

        let mut option_names = BTreeSet::new();
        for (alias, resolved) in &grammar.executable_aliases {
            if alias.is_empty()
                || alias.chars().any(char::is_whitespace)
                || resolved.is_empty()
                || !resolved
                    .chars()
                    .all(|value| value.is_ascii_alphanumeric() || "_+@%.-".contains(value))
                || !resolved
                    .chars()
                    .next()
                    .is_some_and(|value| value.is_ascii_alphanumeric() || value == '_')
            {
                return Err(GuardError::Policy(format!(
                    "command grammar {executable:?} has an invalid executable alias {alias:?}"
                )));
            }
        }
        for (option, arity) in &grammar.options {
            validate_option(option)?;
            if *arity > 8 || !option_names.insert(option.as_str()) {
                return Err(GuardError::Policy(format!(
                    "command grammar {executable:?} has an invalid option arity or duplicate: {option}"
                )));
            }
        }
        for terminal in &grammar.terminal_options {
            validate_option(terminal)?;
            if !option_names.insert(terminal) {
                return Err(GuardError::Policy(format!(
                    "command grammar {executable:?} repeats option {terminal}"
                )));
            }
        }
        let reserved_options = option_names;

        let mut paths = BTreeSet::new();
        for stage in &grammar.stages {
            if !paths.insert(stage.at.clone()) || stage.aliases.is_empty() {
                return Err(GuardError::Policy(format!(
                    "command grammar {executable:?} has a duplicate stage or empty aliases at {:?}",
                    stage.at
                )));
            }
            for token in &stage.at {
                validate_command_token("command grammar stage token", token)?;
            }
            for (alias, canonical) in &stage.aliases {
                match stage.selector {
                    SelectorKind::Option => validate_option(alias)?,
                    SelectorKind::Positional => {
                        validate_command_token("positional selector alias", alias)?;
                        if alias.starts_with('-') {
                            return Err(GuardError::Policy(format!(
                                "positional selector alias must not be an option: {alias}"
                            )));
                        }
                    }
                }
                validate_command_token("canonical selector token", canonical)?;
                if canonical.starts_with('-')
                    || (stage.selector == SelectorKind::Option
                        && reserved_options.contains(alias.as_str()))
                {
                    return Err(GuardError::Policy(format!(
                        "command grammar {executable:?} repeats selector or option {alias}"
                    )));
                }
            }
        }
        for stage in grammar.stages.iter().filter(|stage| !stage.at.is_empty()) {
            let (canonical, parent_path) = stage
                .at
                .split_last()
                .expect("non-root stage paths have a final token");
            let reachable = grammar.stages.iter().any(|parent| {
                parent.at == parent_path && parent.aliases.values().any(|value| value == canonical)
            });
            if !reachable {
                return Err(GuardError::Policy(format!(
                    "command grammar {executable:?} has unreachable stage {:?}",
                    stage.at
                )));
            }
        }
    }
    Ok(())
}

fn validate_command_token(label: &str, token: &str) -> Result<()> {
    if token.is_empty()
        || !token
            .chars()
            .all(|value| value.is_ascii_alphanumeric() || "_./:+@%=-".contains(value))
    {
        return Err(GuardError::Policy(format!("invalid {label}: {token:?}")));
    }
    Ok(())
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
    use serde_json::{Value, json};

    use super::*;

    fn policy_json() -> Value {
        json!({
            "schemaVersion": 3,
            "commandGrammars": {},
            "exact": [],
            "semantic": [{
                "commandPrefix": ["fd"],
                "optionSyntax": {"valueTaking": [], "optionalEquals": []},
                "deny": [{
                    "optionGroups": [["-x"]],
                    "reason": "no",
                    "alternatives": ["safe"]
                }]
            }],
            "shell": {"redirection": {"emptyFile": true}},
            "shellfirm": {
                "enabled": false,
                "minimumSeverity": "High",
                "categories": {},
                "ruleNamespaces": {},
                "rules": {}
            },
            "unknown": {
                "parseError": "deny",
                "dynamicExecutable": "deny",
                "dynamicRelevantOption": "deny",
                "maxDecodeDepth": 8
            }
        })
    }

    fn deserialize(value: Value) -> Policy {
        serde_json::from_value(value).unwrap()
    }

    #[test]
    fn rejects_empty_option_groups() {
        let mut value = policy_json();
        value["semantic"][0]["deny"][0]["optionGroups"] = json!([[]]);
        let policy = deserialize(value);
        assert!(policy.validate_structure().is_err());
    }

    #[test]
    fn absent_shell_policy_defaults_to_allow() {
        let mut value = policy_json();
        value.as_object_mut().unwrap().remove("shell");
        let policy = deserialize(value);
        assert!(policy.shell.redirection.empty_file);
        assert!(policy.validate_structure().is_ok());
    }

    #[test]
    fn rejects_unsupported_schema_versions_and_blank_guidance() {
        for version in [1, 2, 4] {
            let mut value = policy_json();
            value["schemaVersion"] = json!(version);
            assert!(deserialize(value).validate_structure().is_err());
        }

        let mut value = policy_json();
        value["semantic"][0]["guidance"] = json!("   ");
        assert!(deserialize(value).validate_structure().is_err());
    }

    #[test]
    fn rejects_unknown_shell_fields_during_deserialization() {
        let mut value = policy_json();
        value["shell"]["redirection"]["future"] = json!(false);
        assert!(serde_json::from_value::<Policy>(value).is_err());
    }

    #[test]
    fn permits_context_local_selector_aliases_but_rejects_option_collisions() {
        let mut value = policy_json();
        value["commandGrammars"] = json!({
            "demo": {
                "options": {"--mode": 1},
                "terminalOptions": ["--help"],
                "stages": [
                    {
                        "at": [], "selector": "positional",
                        "aliases": {"left": "left", "right": "right"},
                        "unknownOption": "deny", "unknownSelector": "ignore"
                    },
                    {
                        "at": ["left"], "selector": "option",
                        "aliases": {"--select": "select"},
                        "unknownOption": "ignore", "unknownSelector": "deny"
                    },
                    {
                        "at": ["right"], "selector": "option",
                        "aliases": {"--select": "select"},
                        "unknownOption": "ignore", "unknownSelector": "deny"
                    }
                ]
            }
        });
        assert!(deserialize(value.clone()).validate_structure().is_ok());

        value["commandGrammars"]["demo"]["stages"][1]["aliases"] = json!({"--mode": "select"});
        assert!(deserialize(value).validate_structure().is_err());
    }

    #[test]
    fn permits_options_only_command_grammars() {
        let mut value = policy_json();
        value["commandGrammars"] = json!({
            "demo": {
                "options": {"--argstr": 2, "--repair": 0},
                "terminalOptions": ["--help"],
                "stages": []
            }
        });
        assert!(deserialize(value).validate_structure().is_ok());
    }

    #[test]
    fn rejects_unreachable_command_grammar_stages() {
        let mut value = policy_json();
        value["commandGrammars"] = json!({
            "demo": {
                "options": {},
                "terminalOptions": ["--help"],
                "stages": [
                    {
                        "at": [], "selector": "positional",
                        "aliases": {"profile": "profile"},
                        "unknownOption": "deny", "unknownSelector": "ignore"
                    },
                    {
                        "at": ["profil"], "selector": "positional",
                        "aliases": {"mutate": "mutate"},
                        "unknownOption": "deny", "unknownSelector": "deny"
                    }
                ]
            }
        });
        assert!(deserialize(value).validate_structure().is_err());
    }
}
