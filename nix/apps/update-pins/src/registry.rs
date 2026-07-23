#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Target {
    All,
    Hcom,
    AgentSlack,
    AgentBrowser,
    Watchexec,
    Shellfirm,
    Herdr,
    Difit,
    ClaudeCodeSettingsSchema,
    CodexApp,
}

impl Target {
    pub fn name(self) -> &'static str {
        if self == Self::All {
            "all"
        } else {
            target_spec(self)
                .expect("every concrete Target has a registry entry")
                .name
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AssetNaming {
    NameField,
    WatchexecTarget,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TargetKind {
    PairedRelease {
        repository: &'static str,
        pin: &'static str,
        input: &'static str,
    },
    Release {
        repository: &'static str,
        pin: &'static str,
        asset_naming: AssetNaming,
        source_hash: bool,
    },
    UrlHash {
        pin: &'static str,
    },
    Shellfirm {
        repository: &'static str,
        pin: &'static str,
        package: &'static str,
    },
    Difit {
        repository: &'static str,
        npm_package: &'static str,
        pin: &'static str,
        input: &'static str,
        lock: &'static str,
        package: &'static str,
    },
    CodexApp {
        pin: &'static str,
    },
    Unimplemented,
}

impl TargetKind {
    pub fn is_implemented(self) -> bool {
        !matches!(self, Self::Unimplemented)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TargetSpec {
    pub target: Target,
    pub name: &'static str,
    pub kind: TargetKind,
    pub managed_paths: &'static [&'static str],
}

pub static TARGET_SPECS: &[TargetSpec] = &[
    TargetSpec {
        target: Target::Hcom,
        name: "hcom",
        kind: TargetKind::PairedRelease {
            repository: "aannoo/hcom",
            pin: "nix/pins/hcom.json",
            input: "hcom-src",
        },
        managed_paths: &["nix/pins/hcom.json", "flake.nix", "flake.lock"],
    },
    TargetSpec {
        target: Target::AgentSlack,
        name: "agent-slack",
        kind: TargetKind::PairedRelease {
            repository: "stablyai/agent-slack",
            pin: "nix/pins/agent-slack.json",
            input: "agent-slack-skill",
        },
        managed_paths: &["nix/pins/agent-slack.json", "flake.nix", "flake.lock"],
    },
    TargetSpec {
        target: Target::AgentBrowser,
        name: "agent-browser",
        kind: TargetKind::PairedRelease {
            repository: "vercel-labs/agent-browser",
            pin: "nix/pins/agent-browser.json",
            input: "agent-browser-skill",
        },
        managed_paths: &["nix/pins/agent-browser.json", "flake.nix", "flake.lock"],
    },
    TargetSpec {
        target: Target::Watchexec,
        name: "watchexec",
        kind: TargetKind::Release {
            repository: "watchexec/watchexec",
            pin: "nix/pins/watchexec.json",
            asset_naming: AssetNaming::WatchexecTarget,
            source_hash: false,
        },
        managed_paths: &["nix/pins/watchexec.json"],
    },
    TargetSpec {
        target: Target::Shellfirm,
        name: "shellfirm",
        kind: TargetKind::Shellfirm {
            repository: "kaplanelad/shellfirm",
            pin: "nix/pins/shellfirm.json",
            package: "shellfirm",
        },
        managed_paths: &["nix/pins/shellfirm.json"],
    },
    TargetSpec {
        target: Target::Herdr,
        name: "herdr",
        kind: TargetKind::Release {
            repository: "ogulcancelik/herdr",
            pin: "nix/pins/herdr.json",
            asset_naming: AssetNaming::NameField,
            source_hash: true,
        },
        managed_paths: &["nix/pins/herdr.json"],
    },
    TargetSpec {
        target: Target::Difit,
        name: "difit",
        kind: TargetKind::Difit {
            repository: "yoshiko-pg/difit",
            npm_package: "difit",
            pin: "nix/pins/difit.json",
            input: "difit-src",
            lock: "nix/packages/difit/package-lock.json",
            package: "difit",
        },
        managed_paths: &[
            "nix/pins/difit.json",
            "nix/packages/difit/package-lock.json",
            "flake.nix",
            "flake.lock",
        ],
    },
    TargetSpec {
        target: Target::ClaudeCodeSettingsSchema,
        name: "claude-code-settings-schema",
        kind: TargetKind::UrlHash {
            pin: "nix/pins/claude-code-settings-schema.json",
        },
        managed_paths: &["nix/pins/claude-code-settings-schema.json"],
    },
    TargetSpec {
        target: Target::CodexApp,
        name: "codex-app",
        kind: TargetKind::CodexApp {
            pin: "nix/pins/codex-app.json",
        },
        managed_paths: &["nix/pins/codex-app.json"],
    },
];

pub fn target_spec(target: Target) -> Option<&'static TargetSpec> {
    TARGET_SPECS.iter().find(|spec| spec.target == target)
}

pub fn target_by_name(name: &str) -> Option<Target> {
    if name == "all" {
        Some(Target::All)
    } else {
        TARGET_SPECS
            .iter()
            .find(|spec| spec.name == name)
            .map(|spec| spec.target)
    }
}

pub fn unimplemented_target_names() -> Vec<&'static str> {
    TARGET_SPECS
        .iter()
        .filter(|spec| !spec.kind.is_implemented())
        .map(|spec| spec.name)
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;
    use std::path::{Component, Path};

    use super::{TARGET_SPECS, Target, target_by_name, target_spec, unimplemented_target_names};

    #[test]
    fn registry_contains_each_concrete_target_exactly_once() {
        let registered: BTreeSet<_> = TARGET_SPECS.iter().map(|spec| spec.target.name()).collect();
        let expected: BTreeSet<_> = [
            Target::Hcom,
            Target::AgentSlack,
            Target::AgentBrowser,
            Target::Watchexec,
            Target::Shellfirm,
            Target::Herdr,
            Target::Difit,
            Target::ClaudeCodeSettingsSchema,
            Target::CodexApp,
        ]
        .map(Target::name)
        .into_iter()
        .collect();

        assert_eq!(registered, expected);
        assert_eq!(TARGET_SPECS.len(), expected.len());
        assert_eq!(
            TARGET_SPECS
                .iter()
                .map(|spec| spec.target)
                .collect::<Vec<_>>(),
            vec![
                Target::Hcom,
                Target::AgentSlack,
                Target::AgentBrowser,
                Target::Watchexec,
                Target::Shellfirm,
                Target::Herdr,
                Target::Difit,
                Target::ClaudeCodeSettingsSchema,
                Target::CodexApp,
            ]
        );
        assert!(target_spec(Target::All).is_none());
        assert_eq!(target_by_name("all"), Some(Target::All));
        for spec in TARGET_SPECS {
            assert_eq!(target_by_name(spec.name), Some(spec.target));
            assert_eq!(spec.target.name(), spec.name);
            let unique = spec.managed_paths.iter().copied().collect::<BTreeSet<_>>();
            assert_eq!(
                unique.len(),
                spec.managed_paths.len(),
                "{} has duplicate managed paths",
                spec.name
            );
            for managed in spec.managed_paths {
                let path = Path::new(managed);
                assert!(!path.is_absolute() && !path.as_os_str().is_empty());
                assert!(
                    path.components()
                        .all(|component| matches!(component, Component::Normal(_))),
                    "{} has unsafe managed path {managed}",
                    spec.name
                );
            }
            let pin = match spec.kind {
                super::TargetKind::PairedRelease { pin, .. }
                | super::TargetKind::Release { pin, .. }
                | super::TargetKind::UrlHash { pin }
                | super::TargetKind::Shellfirm { pin, .. }
                | super::TargetKind::Difit { pin, .. }
                | super::TargetKind::CodexApp { pin } => pin,
                super::TargetKind::Unimplemented => continue,
            };
            assert!(
                spec.managed_paths.contains(&pin),
                "{} does not own its pin {pin}",
                spec.name
            );
            match spec.kind {
                super::TargetKind::PairedRelease { .. } => {
                    assert!(spec.managed_paths.contains(&"flake.nix"));
                    assert!(spec.managed_paths.contains(&"flake.lock"));
                }
                super::TargetKind::Difit { lock, .. } => {
                    assert!(spec.managed_paths.contains(&lock));
                    assert!(spec.managed_paths.contains(&"flake.nix"));
                    assert!(spec.managed_paths.contains(&"flake.lock"));
                }
                _ => {}
            }
        }
        assert_eq!(target_by_name("unknown"), None);
        assert!(unimplemented_target_names().is_empty());
    }
}
