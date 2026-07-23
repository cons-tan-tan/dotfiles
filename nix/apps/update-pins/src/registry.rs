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
    },
    TargetSpec {
        target: Target::AgentSlack,
        name: "agent-slack",
        kind: TargetKind::PairedRelease {
            repository: "stablyai/agent-slack",
            pin: "nix/pins/agent-slack.json",
            input: "agent-slack-skill",
        },
    },
    TargetSpec {
        target: Target::AgentBrowser,
        name: "agent-browser",
        kind: TargetKind::PairedRelease {
            repository: "vercel-labs/agent-browser",
            pin: "nix/pins/agent-browser.json",
            input: "agent-browser-skill",
        },
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
    },
    TargetSpec {
        target: Target::Shellfirm,
        name: "shellfirm",
        kind: TargetKind::Unimplemented,
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
    },
    TargetSpec {
        target: Target::Difit,
        name: "difit",
        kind: TargetKind::Unimplemented,
    },
    TargetSpec {
        target: Target::ClaudeCodeSettingsSchema,
        name: "claude-code-settings-schema",
        kind: TargetKind::UrlHash {
            pin: "nix/pins/claude-code-settings-schema.json",
        },
    },
    TargetSpec {
        target: Target::CodexApp,
        name: "codex-app",
        kind: TargetKind::Unimplemented,
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

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::{TARGET_SPECS, Target, target_by_name, target_spec};

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
        assert!(target_spec(Target::All).is_none());
        assert_eq!(target_by_name("all"), Some(Target::All));
        for spec in TARGET_SPECS {
            assert_eq!(target_by_name(spec.name), Some(spec.target));
            assert_eq!(spec.target.name(), spec.name);
        }
        assert_eq!(target_by_name("unknown"), None);
    }
}
