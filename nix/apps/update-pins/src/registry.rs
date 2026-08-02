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
pub enum PublishedArtifact {
    NpmRegistryTarball {
        package: &'static str,
        source_hash_field: &'static str,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PairedSource {
    pub repository: &'static str,
    pub input: &'static str,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PnpmMajor {
    V11,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DependencyScope {
    Production,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DependencyProvenance {
    UpstreamPnpm {
        source: PairedSource,
        lock_path: &'static str,
        workspace_path: &'static str,
        workspace: &'static str,
        pnpm: PnpmMajor,
        scope: DependencyScope,
    },
}

impl DependencyProvenance {
    pub fn source(self) -> PairedSource {
        match self {
            Self::UpstreamPnpm { source, .. } => source,
        }
    }

    pub fn nix_contract(self) -> serde_json::Value {
        match self {
            Self::UpstreamPnpm {
                lock_path,
                workspace_path,
                workspace,
                pnpm,
                scope,
                ..
            } => serde_json::json!({
                "kind": "upstream-pnpm",
                "lockPath": lock_path,
                "workspacePath": workspace_path,
                "workspace": workspace,
                "pnpmMajor": match pnpm {
                    PnpmMajor::V11 => 11,
                },
                "scope": match scope {
                    DependencyScope::Production => "production",
                },
            }),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PackageBuildSpec {
    pub package_attr: &'static str,
    pub pin_override: &'static str,
    pub dependency_hash_field: &'static str,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PublishedNodePackageSpec {
    pub pin: &'static str,
    pub artifact: PublishedArtifact,
    pub dependencies: DependencyProvenance,
    pub build: PackageBuildSpec,
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
        lock: &'static str,
        guard_manifest: &'static str,
        guard_lock: &'static str,
        package: &'static str,
    },
    PublishedNodePackage(PublishedNodePackageSpec),
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
            lock: "nix/packages/shellfirm/Cargo.lock",
            guard_manifest: "nix/packages/agent-command-guard/Cargo.toml",
            guard_lock: "nix/packages/agent-command-guard/Cargo.lock",
            package: "shellfirm",
        },
        managed_paths: &[
            "nix/pins/shellfirm.json",
            "nix/packages/shellfirm/Cargo.lock",
            "nix/packages/agent-command-guard/Cargo.toml",
            "nix/packages/agent-command-guard/Cargo.lock",
        ],
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
        kind: TargetKind::PublishedNodePackage(PublishedNodePackageSpec {
            pin: "nix/pins/difit.json",
            artifact: PublishedArtifact::NpmRegistryTarball {
                package: "difit",
                source_hash_field: "srcHash",
            },
            dependencies: DependencyProvenance::UpstreamPnpm {
                source: PairedSource {
                    repository: "yoshiko-pg/difit",
                    input: "difit-src",
                },
                lock_path: "pnpm-lock.yaml",
                workspace_path: "pnpm-workspace.yaml",
                workspace: "difit",
                pnpm: PnpmMajor::V11,
                scope: DependencyScope::Production,
            },
            build: PackageBuildSpec {
                package_attr: "difit",
                pin_override: "difitPin",
                dependency_hash_field: "pnpmDepsHash",
            },
        }),
        managed_paths: &["nix/pins/difit.json", "flake.nix", "flake.lock"],
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
    fn registry_target_and_name_keys_are_unique() {
        let mut targets = Vec::new();
        let mut names = BTreeSet::new();
        for spec in TARGET_SPECS {
            assert!(
                !targets.contains(&spec.target),
                "{} reuses a target key",
                spec.name
            );
            assert!(names.insert(spec.name), "{} reuses a name key", spec.name);
            targets.push(spec.target);
        }
    }

    #[test]
    fn registry_keys_round_trip_to_the_same_spec() {
        for spec in TARGET_SPECS {
            assert_eq!(target_spec(spec.target), Some(spec));
            assert_eq!(target_by_name(spec.name), Some(spec.target));
            assert_eq!(spec.target.name(), spec.name);
        }
    }

    #[test]
    fn all_is_a_parser_only_special_case() {
        assert!(target_spec(Target::All).is_none());
        assert_eq!(target_by_name("all"), Some(Target::All));
        assert!(TARGET_SPECS.iter().all(|spec| spec.name != "all"));
        assert_eq!(target_by_name("unknown"), None);
    }

    #[test]
    fn managed_paths_are_safe_and_unique_within_each_target() {
        for spec in TARGET_SPECS {
            assert!(
                !spec.managed_paths.is_empty(),
                "{} has no managed paths",
                spec.name
            );
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
        }
    }

    #[test]
    fn target_kind_contracts_are_owned_by_their_specs() {
        for spec in TARGET_SPECS {
            let pin = match spec.kind {
                super::TargetKind::PairedRelease { pin, .. }
                | super::TargetKind::Release { pin, .. }
                | super::TargetKind::UrlHash { pin }
                | super::TargetKind::Shellfirm { pin, .. }
                | super::TargetKind::PublishedNodePackage(super::PublishedNodePackageSpec {
                    pin,
                    ..
                })
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
                super::TargetKind::PublishedNodePackage(package) => {
                    assert_eq!(
                        spec.managed_paths,
                        &["nix/pins/difit.json", "flake.nix", "flake.lock"]
                    );
                    assert_eq!(
                        package.artifact,
                        super::PublishedArtifact::NpmRegistryTarball {
                            package: "difit",
                            source_hash_field: "srcHash",
                        }
                    );
                    assert_eq!(
                        package.dependencies,
                        super::DependencyProvenance::UpstreamPnpm {
                            source: super::PairedSource {
                                repository: "yoshiko-pg/difit",
                                input: "difit-src",
                            },
                            lock_path: "pnpm-lock.yaml",
                            workspace_path: "pnpm-workspace.yaml",
                            workspace: "difit",
                            pnpm: super::PnpmMajor::V11,
                            scope: super::DependencyScope::Production,
                        }
                    );
                    assert_eq!(
                        package.dependencies.nix_contract(),
                        serde_json::json!({
                            "kind": "upstream-pnpm",
                            "lockPath": "pnpm-lock.yaml",
                            "workspacePath": "pnpm-workspace.yaml",
                            "workspace": "difit",
                            "pnpmMajor": 11,
                            "scope": "production",
                        })
                    );
                    assert_eq!(
                        package.build,
                        super::PackageBuildSpec {
                            package_attr: "difit",
                            pin_override: "difitPin",
                            dependency_hash_field: "pnpmDepsHash",
                        }
                    );
                }
                super::TargetKind::Shellfirm { lock, .. } => {
                    assert!(spec.managed_paths.contains(&lock));
                }
                _ => {}
            }
        }
        assert!(unimplemented_target_names().is_empty());
    }
}
