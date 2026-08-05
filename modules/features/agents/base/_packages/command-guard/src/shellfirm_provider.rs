use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
};

use shellfirm::{
    checks::{self, Check, Severity},
    env::Environment,
};

use crate::{
    error::{GuardError, Result},
    policy::{Policy, ShellfirmPolicy},
    shell::Projection,
};

pub struct ValidatedPolicy {
    pub policy: Policy,
    selected_checks: Vec<Check>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellfirmMatch {
    pub id: String,
    pub description: String,
    pub severity: Severity,
    pub alternative: Option<String>,
}

#[derive(Debug, Clone, Copy)]
struct CatalogMeta<'a> {
    id: &'a str,
    namespace: &'a str,
    from: &'a str,
    severity: Severity,
}

pub fn validate_policy(policy: Policy) -> Result<ValidatedPolicy> {
    policy.validate_structure()?;
    let checks = checks::get_all().map_err(|error| GuardError::Shellfirm(error.to_string()))?;
    let selected_checks = select_checks(&policy.shellfirm, checks)?;
    Ok(ValidatedPolicy {
        policy,
        selected_checks,
    })
}

impl ValidatedPolicy {
    pub fn effective_shellfirm_ids(&self) -> Vec<String> {
        let mut ids = self
            .selected_checks
            .iter()
            .map(|check| check.id.clone())
            .collect::<Vec<_>>();
        ids.sort();
        ids
    }

    pub fn shellfirm_matches(&self, projection: &Projection, cwd: &Path) -> Vec<ShellfirmMatch> {
        if self.selected_checks.is_empty() {
            return Vec::new();
        }
        let env = GuardEnvironment {
            cwd: cwd.to_path_buf(),
        };
        let mut matches = Vec::new();
        for check in &self.selected_checks {
            let origin_valid = check
                .test
                .find_iter(projection.text())
                .any(|candidate| projection.is_executable_match(candidate.range()));
            if !origin_valid {
                continue;
            }
            if checks::run_check_on_command_with_env(
                std::slice::from_ref(check),
                projection.text(),
                &env,
            )
            .is_empty()
            {
                continue;
            }
            matches.push(ShellfirmMatch {
                id: check.id.clone(),
                description: check.description.clone(),
                severity: check.severity,
                alternative: check.alternative.clone(),
            });
        }
        matches
    }
}

fn select_checks(policy: &ShellfirmPolicy, checks: Vec<Check>) -> Result<Vec<Check>> {
    let mut seen_ids = BTreeSet::new();
    let mut categories = BTreeSet::new();
    let mut namespaces = BTreeSet::new();
    let mut metadata = Vec::with_capacity(checks.len());

    for check in &checks {
        if !seen_ids.insert(check.id.as_str()) {
            return Err(GuardError::Policy(format!(
                "duplicate Shellfirm catalog ID {}",
                check.id
            )));
        }
        let Some((namespace, name)) = check.id.split_once(':') else {
            return Err(GuardError::Policy(format!(
                "Shellfirm catalog ID has no namespace: {}",
                check.id
            )));
        };
        if namespace.is_empty() || name.is_empty() {
            return Err(GuardError::Policy(format!(
                "Shellfirm catalog ID is invalid: {}",
                check.id
            )));
        }
        categories.insert(check.from.as_str());
        namespaces.insert(namespace);
        metadata.push(CatalogMeta {
            id: &check.id,
            namespace,
            from: &check.from,
            severity: check.severity,
        });
    }

    validate_catalog_selectors(policy, &categories, &namespaces, &seen_ids)?;
    if !policy.enabled {
        return Ok(Vec::new());
    }

    let selected = metadata
        .iter()
        .enumerate()
        .filter_map(|(index, meta)| is_selected(policy, *meta).then_some(index))
        .map(|index| checks[index].clone())
        .collect::<Vec<_>>();
    if selected.is_empty() {
        return Err(GuardError::Policy(
            "enabled Shellfirm selector produced no effective rules".to_owned(),
        ));
    }
    Ok(selected)
}

fn validate_catalog_selectors(
    policy: &ShellfirmPolicy,
    categories: &BTreeSet<&str>,
    namespaces: &BTreeSet<&str>,
    ids: &BTreeSet<&str>,
) -> Result<()> {
    for category in policy.categories.keys() {
        if !categories.contains(category.as_str()) {
            return Err(GuardError::Policy(format!(
                "unknown Shellfirm category {category}"
            )));
        }
    }
    for namespace in policy.rule_namespaces.keys() {
        if !namespaces.contains(namespace.as_str()) {
            return Err(GuardError::Policy(format!(
                "unknown Shellfirm rule namespace {namespace}"
            )));
        }
    }
    for id in policy.rules.keys() {
        if !ids.contains(id.as_str()) {
            return Err(GuardError::Policy(format!(
                "unknown individual Shellfirm rule {id}"
            )));
        }
    }
    Ok(())
}

fn is_selected(policy: &ShellfirmPolicy, meta: CatalogMeta<'_>) -> bool {
    if let Some(decision) = policy.rules.get(meta.id) {
        return *decision;
    }
    if let Some(decision) = policy.rule_namespaces.get(meta.namespace) {
        return *decision;
    }
    policy.categories.get(meta.from).copied().unwrap_or(false)
        && meta.severity >= policy.minimum_severity
}

struct GuardEnvironment {
    cwd: PathBuf,
}

impl Environment for GuardEnvironment {
    fn var(&self, _key: &str) -> Option<String> {
        None
    }

    fn current_dir(&self) -> shellfirm::error::Result<PathBuf> {
        Ok(self.cwd.clone())
    }

    fn path_exists(&self, path: &Path) -> bool {
        let path = if path.is_absolute() {
            path.to_path_buf()
        } else {
            self.cwd.join(path)
        };
        path.exists()
    }

    fn home_dir(&self) -> Option<PathBuf> {
        std::env::var_os("HOME").map(PathBuf::from)
    }

    fn run_command(&self, _cmd: &str, _args: &[&str], _timeout_ms: u64) -> Option<String> {
        None
    }

    fn read_file(&self, _path: &Path) -> shellfirm::error::Result<String> {
        Err(shellfirm::error::Error::Other(
            "file reads are disabled in the agent command guard".to_owned(),
        ))
    }

    fn find_file_upward(&self, _start: &Path, _filename: &str) -> Option<PathBuf> {
        None
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    fn policy() -> ShellfirmPolicy {
        ShellfirmPolicy {
            enabled: true,
            minimum_severity: Severity::High,
            categories: BTreeMap::from([("git".to_owned(), true)]),
            rule_namespaces: BTreeMap::from([("git-strict".to_owned(), false)]),
            rules: BTreeMap::new(),
        }
    }

    #[test]
    fn precedence_is_exact_then_namespace_then_category() {
        let mut policy = policy();
        let high = CatalogMeta {
            id: "git:force_push",
            namespace: "git",
            from: "git",
            severity: Severity::High,
        };
        assert!(is_selected(&policy, high));

        policy.rule_namespaces.insert("git".to_owned(), false);
        assert!(!is_selected(&policy, high));

        policy.rules.insert("git:force_push".to_owned(), true);
        assert!(is_selected(&policy, high));

        policy.rules.insert("git:force_push".to_owned(), false);
        assert!(!is_selected(&policy, high));
    }

    #[test]
    fn exact_true_can_include_below_threshold() {
        let mut policy = policy();
        let low = CatalogMeta {
            id: "git:low",
            namespace: "git",
            from: "git",
            severity: Severity::Low,
        };
        assert!(!is_selected(&policy, low));
        policy.rules.insert("git:low".to_owned(), true);
        assert!(is_selected(&policy, low));
    }
}
