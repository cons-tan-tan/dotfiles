use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};

use serde_json::Value;

use crate::registry::{TARGET_SPECS, Target, TargetKind, TargetSpec};
use crate::targets::paired_version;
use crate::validation::CANONICAL_SYSTEMS;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FileState {
    pub path: &'static str,
    pub bytes: Option<Vec<u8>>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Change {
    pub target: Target,
    pub kind: ChangeKind,
    pub old: DisplayValue,
    pub new: DisplayValue,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ChangeKind {
    Version,
    Url,
    SourceHash,
    DependencyHash,
    SchemaHash,
    AppHash,
    AssetHash(String),
    Lockfile(String),
    FlakeInput(String),
    ManagedFile(String),
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DisplayValue {
    Text(String),
    Redacted,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Outcome {
    Unchanged,
    Applied(Vec<Change>),
    Candidate(Vec<Change>),
    RolledBack(Vec<Change>),
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Ledger {
    changes: Vec<Change>,
}

impl Ledger {
    pub fn extend(&mut self, changes: impl IntoIterator<Item = Change>) {
        self.changes.extend(changes);
    }

    pub fn is_empty(&self) -> bool {
        self.changes.is_empty()
    }

    pub fn applied(&self) -> Outcome {
        if self.is_empty() {
            Outcome::Unchanged
        } else {
            Outcome::Applied(self.ordered())
        }
    }

    pub fn candidate(&self) -> Outcome {
        if self.is_empty() {
            Outcome::Unchanged
        } else {
            Outcome::Candidate(self.ordered())
        }
    }

    pub fn rolled_back(&self) -> Outcome {
        if self.is_empty() {
            Outcome::Unchanged
        } else {
            Outcome::RolledBack(self.ordered())
        }
    }

    fn ordered(&self) -> Vec<Change> {
        let mut changes = self.changes.clone();
        changes.sort_by(compare_changes);
        changes
    }
}

impl Outcome {
    pub fn render(&self) -> Option<String> {
        let (heading, changes) = match self {
            Self::Unchanged => return None,
            Self::Applied(changes) => ("Applied changes:", changes),
            Self::Candidate(changes) => ("Candidate changes:", changes),
            Self::RolledBack(changes) => ("Rolled back candidate changes:", changes),
        };
        let mut rendered = String::from(heading);
        let mut current_target = None;
        for change in changes {
            if current_target != Some(change.target) {
                current_target = Some(change.target);
                rendered.push_str("\n  ");
                rendered.push_str(change.target.name());
                rendered.push(':');
            }
            rendered.push_str("\n    - ");
            rendered.push_str(&change.render());
        }
        Some(rendered)
    }
}

impl Change {
    fn render(&self) -> String {
        let label = self.kind.label();
        match (&self.old, &self.new) {
            (DisplayValue::Text(old), DisplayValue::Text(new))
                if safe_display_text(old) && safe_display_text(new) =>
            {
                format!("{label}: {old} -> {new}")
            }
            _ => format!("{label}: changed"),
        }
    }
}

impl ChangeKind {
    fn label(&self) -> String {
        match self {
            Self::Version => "version".to_owned(),
            Self::Url => "URL".to_owned(),
            Self::SourceHash => "source hash".to_owned(),
            Self::DependencyHash => "dependency hash".to_owned(),
            Self::SchemaHash => "schema hash".to_owned(),
            Self::AppHash => "app hash".to_owned(),
            Self::AssetHash(system) if CANONICAL_SYSTEMS.contains(&system.as_str()) => {
                format!("asset hash [{system}]")
            }
            Self::AssetHash(_) => "asset hash [unknown system]".to_owned(),
            Self::Lockfile(path) => format!("lockfile [{path}]"),
            Self::FlakeInput(input) => format!("flake input [{input}]"),
            Self::ManagedFile(path) => format!("managed file [{path}]"),
        }
    }

    fn order_key(&self) -> (u8, usize, &str) {
        match self {
            Self::Version => (0, 0, ""),
            Self::Url => (1, 0, ""),
            Self::SourceHash => (2, 0, ""),
            Self::DependencyHash => (3, 0, ""),
            Self::SchemaHash => (4, 0, ""),
            Self::AppHash => (5, 0, ""),
            Self::AssetHash(system) => (
                6,
                CANONICAL_SYSTEMS
                    .iter()
                    .position(|candidate| candidate == system)
                    .unwrap_or(usize::MAX),
                system,
            ),
            Self::Lockfile(path) => (7, 0, path),
            Self::FlakeInput(input) => (8, 0, input),
            Self::ManagedFile(path) => (9, 0, path),
        }
    }
}

fn safe_display_text(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'+' | b'-' | b'_'))
}

pub fn diff_target(spec: &TargetSpec, before: &[FileState], after: &[FileState]) -> Vec<Change> {
    let mut changes = Vec::new();
    let mut represented = BTreeSet::new();
    match spec.kind {
        TargetKind::PairedRelease {
            repository,
            pin,
            input,
        } => {
            record_paired_version(
                spec,
                repository,
                before,
                after,
                &mut represented,
                &mut changes,
            );
            record_pin_changes(
                spec,
                pin,
                before,
                after,
                PinFields::Assets,
                &mut represented,
                &mut changes,
            );
            record_changed_file(
                spec,
                "flake.lock",
                ChangeKind::FlakeInput(input.to_owned()),
                before,
                after,
                &mut represented,
                &mut changes,
            );
        }
        TargetKind::Release {
            pin, source_hash, ..
        } => {
            record_pin_changes(
                spec,
                pin,
                before,
                after,
                PinFields::Release { source_hash },
                &mut represented,
                &mut changes,
            );
        }
        TargetKind::UrlHash { pin } => {
            record_pin_changes(
                spec,
                pin,
                before,
                after,
                PinFields::Schema,
                &mut represented,
                &mut changes,
            );
        }
        TargetKind::Shellfirm { pin, lock, .. } => {
            record_pin_changes(
                spec,
                pin,
                before,
                after,
                PinFields::Shellfirm,
                &mut represented,
                &mut changes,
            );
            record_changed_file(
                spec,
                lock,
                ChangeKind::Lockfile(lock.to_owned()),
                before,
                after,
                &mut represented,
                &mut changes,
            );
        }
        TargetKind::PublishedNodePackage(package) => {
            let paired = package.dependencies.source();
            let crate::registry::PublishedArtifact::NpmRegistryTarball {
                source_hash_field, ..
            } = package.artifact;
            record_paired_version(
                spec,
                paired.repository,
                before,
                after,
                &mut represented,
                &mut changes,
            );
            record_pin_changes(
                spec,
                package.pin,
                before,
                after,
                PinFields::PublishedNodePackage {
                    source_hash_field,
                    dependency_hash_field: package.build.dependency_hash_field,
                },
                &mut represented,
                &mut changes,
            );
            record_changed_file(
                spec,
                "flake.lock",
                ChangeKind::FlakeInput(paired.input.to_owned()),
                before,
                after,
                &mut represented,
                &mut changes,
            );
        }
        TargetKind::CodexApp { pin } => {
            record_pin_changes(
                spec,
                pin,
                before,
                after,
                PinFields::CodexApp,
                &mut represented,
                &mut changes,
            );
        }
        TargetKind::Unimplemented => {}
    }

    for path in spec.managed_paths {
        if file_changed(path, before, after) && !represented.contains(path) {
            changes.push(redacted_change(
                spec.target,
                ChangeKind::ManagedFile((*path).to_owned()),
            ));
        }
    }
    changes
}

#[derive(Clone, Copy)]
enum PinFields {
    Assets,
    Release {
        source_hash: bool,
    },
    Schema,
    Shellfirm,
    PublishedNodePackage {
        source_hash_field: &'static str,
        dependency_hash_field: &'static str,
    },
    CodexApp,
}

fn record_pin_changes(
    spec: &TargetSpec,
    path: &'static str,
    before: &[FileState],
    after: &[FileState],
    fields: PinFields,
    represented: &mut BTreeSet<&'static str>,
    changes: &mut Vec<Change>,
) {
    if !file_changed(path, before, after) {
        return;
    }
    let Some((old, new)) = json_pair(path, before, after) else {
        return;
    };
    let start = changes.len();
    match fields {
        PinFields::Assets => record_assets(spec.target, &old, &new, changes),
        PinFields::Release { source_hash } => {
            record_text_field(
                spec.target,
                ChangeKind::Version,
                &old,
                &new,
                "version",
                changes,
            );
            if source_hash {
                record_redacted_field(
                    spec.target,
                    ChangeKind::SourceHash,
                    &old,
                    &new,
                    "srcHash",
                    changes,
                );
            }
            record_assets(spec.target, &old, &new, changes);
        }
        PinFields::Schema => {
            record_redacted_field(spec.target, ChangeKind::Url, &old, &new, "url", changes);
            record_redacted_field(
                spec.target,
                ChangeKind::SchemaHash,
                &old,
                &new,
                "hash",
                changes,
            );
        }
        PinFields::Shellfirm => {
            record_text_field(
                spec.target,
                ChangeKind::Version,
                &old,
                &new,
                "version",
                changes,
            );
            record_redacted_field(
                spec.target,
                ChangeKind::SourceHash,
                &old,
                &new,
                "srcHash",
                changes,
            );
        }
        PinFields::PublishedNodePackage {
            source_hash_field,
            dependency_hash_field,
        } => {
            record_redacted_field(
                spec.target,
                ChangeKind::SourceHash,
                &old,
                &new,
                source_hash_field,
                changes,
            );
            record_redacted_field(
                spec.target,
                ChangeKind::DependencyHash,
                &old,
                &new,
                dependency_hash_field,
                changes,
            );
        }
        PinFields::CodexApp => {
            record_text_field(
                spec.target,
                ChangeKind::Version,
                &old,
                &new,
                "version",
                changes,
            );
            record_redacted_field(spec.target, ChangeKind::Url, &old, &new, "url", changes);
            record_redacted_field(
                spec.target,
                ChangeKind::AppHash,
                &old,
                &new,
                "hash",
                changes,
            );
        }
    }
    if changes.len() > start {
        represented.insert(path);
    }
}

fn record_paired_version(
    spec: &TargetSpec,
    repository: &str,
    before: &[FileState],
    after: &[FileState],
    represented: &mut BTreeSet<&'static str>,
    changes: &mut Vec<Change>,
) {
    let path = "flake.nix";
    if !file_changed(path, before, after) {
        return;
    }
    let Some(old) = state(path, before).and_then(|bytes| bytes.as_deref()) else {
        return;
    };
    let Some(new) = state(path, after).and_then(|bytes| bytes.as_deref()) else {
        return;
    };
    let (Ok(old), Ok(new)) = (
        paired_version(old, repository),
        paired_version(new, repository),
    ) else {
        return;
    };
    if old != new {
        changes.push(Change {
            target: spec.target,
            kind: ChangeKind::Version,
            old: DisplayValue::Text(old),
            new: DisplayValue::Text(new),
        });
        represented.insert(path);
    }
}

fn record_changed_file(
    spec: &TargetSpec,
    path: &'static str,
    kind: ChangeKind,
    before: &[FileState],
    after: &[FileState],
    represented: &mut BTreeSet<&'static str>,
    changes: &mut Vec<Change>,
) {
    if file_changed(path, before, after) {
        changes.push(redacted_change(spec.target, kind));
        represented.insert(path);
    }
}

fn record_text_field(
    target: Target,
    kind: ChangeKind,
    old: &Value,
    new: &Value,
    field: &str,
    changes: &mut Vec<Change>,
) {
    let old = old.get(field).and_then(Value::as_str);
    let new = new.get(field).and_then(Value::as_str);
    if let (Some(old), Some(new)) = (old, new)
        && old != new
    {
        changes.push(Change {
            target,
            kind,
            old: DisplayValue::Text(old.to_owned()),
            new: DisplayValue::Text(new.to_owned()),
        });
    }
}

fn record_redacted_field(
    target: Target,
    kind: ChangeKind,
    old: &Value,
    new: &Value,
    field: &str,
    changes: &mut Vec<Change>,
) {
    if old.get(field) != new.get(field) {
        changes.push(redacted_change(target, kind));
    }
}

fn record_assets(target: Target, old: &Value, new: &Value, changes: &mut Vec<Change>) {
    let old_assets = asset_hashes(old);
    let new_assets = asset_hashes(new);
    let systems = old_assets
        .keys()
        .chain(new_assets.keys())
        .cloned()
        .collect::<BTreeSet<_>>();
    for system in systems {
        if old_assets.get(&system) != new_assets.get(&system) {
            changes.push(redacted_change(target, ChangeKind::AssetHash(system)));
        }
    }
}

fn asset_hashes(value: &Value) -> BTreeMap<String, Option<String>> {
    value
        .get("assets")
        .and_then(Value::as_object)
        .map(|assets| {
            assets
                .iter()
                .map(|(system, asset)| {
                    (
                        system.clone(),
                        asset
                            .get("hash")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned),
                    )
                })
                .collect()
        })
        .unwrap_or_default()
}

fn redacted_change(target: Target, kind: ChangeKind) -> Change {
    Change {
        target,
        kind,
        old: DisplayValue::Redacted,
        new: DisplayValue::Redacted,
    }
}

fn json_pair(path: &str, before: &[FileState], after: &[FileState]) -> Option<(Value, Value)> {
    let old = state(path, before)?.as_deref()?;
    let new = state(path, after)?.as_deref()?;
    Some((
        serde_json::from_slice(old).ok()?,
        serde_json::from_slice(new).ok()?,
    ))
}

fn file_changed(path: &str, before: &[FileState], after: &[FileState]) -> bool {
    state(path, before) != state(path, after)
}

fn state<'a>(path: &str, states: &'a [FileState]) -> Option<&'a Option<Vec<u8>>> {
    states
        .iter()
        .find(|state| state.path == path)
        .map(|state| &state.bytes)
}

fn compare_changes(left: &Change, right: &Change) -> Ordering {
    target_order(left.target)
        .cmp(&target_order(right.target))
        .then_with(|| left.kind.order_key().cmp(&right.kind.order_key()))
}

fn target_order(target: Target) -> usize {
    TARGET_SPECS
        .iter()
        .position(|spec| spec.target == target)
        .unwrap_or(usize::MAX)
}

#[cfg(test)]
mod tests {
    use super::{Change, ChangeKind, DisplayValue, FileState, Ledger, Outcome, diff_target};
    use crate::registry::{Target, target_spec};

    fn change(target: Target, kind: ChangeKind) -> Change {
        Change {
            target,
            kind,
            old: DisplayValue::Redacted,
            new: DisplayValue::Redacted,
        }
    }

    fn state(path: &'static str, bytes: impl Into<Vec<u8>>) -> FileState {
        FileState {
            path,
            bytes: Some(bytes.into()),
        }
    }

    #[test]
    fn rendering_uses_registry_field_and_asset_order_not_completion_order() {
        let mut ledger = Ledger::default();
        ledger.extend([
            change(Target::Herdr, ChangeKind::AssetHash("x86_64-linux".into())),
            change(Target::Hcom, ChangeKind::AssetHash("x86_64-linux".into())),
            change(Target::Hcom, ChangeKind::AssetHash("aarch64-darwin".into())),
            Change {
                target: Target::Hcom,
                kind: ChangeKind::Version,
                old: DisplayValue::Text("1.0.0".into()),
                new: DisplayValue::Text("2.0.0".into()),
            },
        ]);

        assert_eq!(
            ledger.applied().render().expect("applied report"),
            "Applied changes:\n  hcom:\n    - version: 1.0.0 -> 2.0.0\n    - asset hash \
             [aarch64-darwin]: changed\n    - asset hash [x86_64-linux]: changed\n  herdr:\n    - \
             asset hash [x86_64-linux]: changed"
        );
    }

    #[test]
    fn every_change_kind_uses_an_explicit_field_order() {
        let mut ledger = Ledger::default();
        ledger.extend([
            change(Target::Difit, ChangeKind::ManagedFile("pin.json".into())),
            change(Target::Difit, ChangeKind::FlakeInput("input".into())),
            change(Target::Difit, ChangeKind::Lockfile("lock.json".into())),
            change(Target::Difit, ChangeKind::AssetHash("x86_64-linux".into())),
            change(Target::Difit, ChangeKind::AppHash),
            change(Target::Difit, ChangeKind::SchemaHash),
            change(Target::Difit, ChangeKind::DependencyHash),
            change(Target::Difit, ChangeKind::SourceHash),
            change(Target::Difit, ChangeKind::Url),
            change(Target::Difit, ChangeKind::Version),
        ]);

        assert_eq!(
            ledger
                .ordered()
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [
                ChangeKind::Version,
                ChangeKind::Url,
                ChangeKind::SourceHash,
                ChangeKind::DependencyHash,
                ChangeKind::SchemaHash,
                ChangeKind::AppHash,
                ChangeKind::AssetHash("x86_64-linux".into()),
                ChangeKind::Lockfile("lock.json".into()),
                ChangeKind::FlakeInput("input".into()),
                ChangeKind::ManagedFile("pin.json".into()),
            ]
        );
    }

    #[test]
    fn unchanged_ledger_has_no_report() {
        assert_eq!(Ledger::default().applied(), Outcome::Unchanged);
        assert_eq!(Ledger::default().candidate(), Outcome::Unchanged);
        assert_eq!(Ledger::default().rolled_back().render(), None);
    }

    #[test]
    fn candidate_report_is_ordered_and_redacted() {
        let secret_hash = "sha256-secret-value";
        let secret_url = "https://user:password@example.invalid/app.zip?token=secret";
        let mut ledger = Ledger::default();
        ledger.extend([
            Change {
                target: Target::Herdr,
                kind: ChangeKind::SourceHash,
                old: DisplayValue::Text(secret_hash.into()),
                new: DisplayValue::Redacted,
            },
            Change {
                target: Target::Hcom,
                kind: ChangeKind::Url,
                old: DisplayValue::Text(secret_url.into()),
                new: DisplayValue::Redacted,
            },
            Change {
                target: Target::Hcom,
                kind: ChangeKind::Version,
                old: DisplayValue::Text("1.0.0".into()),
                new: DisplayValue::Text("2.0.0".into()),
            },
        ]);

        let rendered = ledger.candidate().render().expect("candidate report");
        assert_eq!(
            rendered,
            "Candidate changes:\n  hcom:\n    - version: 1.0.0 -> 2.0.0\n    - URL: \
             changed\n  herdr:\n    - source hash: changed"
        );
        assert!(!rendered.contains(secret_hash));
        assert!(!rendered.contains(secret_url));
    }

    #[test]
    fn malformed_candidate_falls_back_to_a_managed_file_change() {
        let spec = target_spec(Target::Herdr).expect("herdr spec");
        let before = [super::FileState {
            path: "nix/pins/herdr.json",
            bytes: Some(br#"{"version":"1.0.0"}"#.to_vec()),
        }];
        let after = [super::FileState {
            path: "nix/pins/herdr.json",
            bytes: Some(b"{invalid".to_vec()),
        }];
        assert_eq!(
            diff_target(spec, &before, &after),
            [change(
                Target::Herdr,
                ChangeKind::ManagedFile("nix/pins/herdr.json".into())
            )]
        );
    }

    #[test]
    fn semantic_diffs_cover_every_target_kind() {
        let hcom = target_spec(Target::Hcom).expect("hcom spec");
        let hcom_before = [
            state(
                "nix/pins/hcom.json",
                br#"{"assets":{"aarch64-darwin":{"hash":"sha256-old"}}}"#,
            ),
            state("flake.nix", br#"url = "github:aannoo/hcom/v1.0.0";"#),
            state("flake.lock", br#"{"nodes":{"old":{}}}"#),
        ];
        let hcom_after = [
            state(
                "nix/pins/hcom.json",
                br#"{"assets":{"aarch64-darwin":{"hash":"sha256-new"}}}"#,
            ),
            state("flake.nix", br#"url = "github:aannoo/hcom/v2.0.0";"#),
            state("flake.lock", br#"{"nodes":{"new":{}}}"#),
        ];
        assert_eq!(
            diff_target(hcom, &hcom_before, &hcom_after)
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [
                ChangeKind::Version,
                ChangeKind::AssetHash("aarch64-darwin".into()),
                ChangeKind::FlakeInput("hcom-src".into()),
            ]
        );

        let herdr = target_spec(Target::Herdr).expect("herdr spec");
        let herdr_before = [state(
            "nix/pins/herdr.json",
            br#"{"version":"1.0.0","srcHash":"sha256-old","assets":{"x86_64-linux":{"hash":"sha256-old"}}}"#,
        )];
        let herdr_after = [state(
            "nix/pins/herdr.json",
            br#"{"version":"2.0.0","srcHash":"sha256-new","assets":{"x86_64-linux":{"hash":"sha256-new"}}}"#,
        )];
        assert_eq!(
            diff_target(herdr, &herdr_before, &herdr_after)
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [
                ChangeKind::Version,
                ChangeKind::SourceHash,
                ChangeKind::AssetHash("x86_64-linux".into()),
            ]
        );

        let shellfirm = target_spec(Target::Shellfirm).expect("shellfirm spec");
        let shellfirm_before = [
            state(
                "nix/pins/shellfirm.json",
                br#"{"version":"1.0.0","srcHash":"sha256-old"}"#,
            ),
            state("nix/packages/shellfirm/Cargo.lock", b"old lock"),
        ];
        let shellfirm_after = [
            state(
                "nix/pins/shellfirm.json",
                br#"{"version":"2.0.0","srcHash":"sha256-new"}"#,
            ),
            state("nix/packages/shellfirm/Cargo.lock", b"new lock"),
        ];
        assert_eq!(
            diff_target(shellfirm, &shellfirm_before, &shellfirm_after)
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [
                ChangeKind::Version,
                ChangeKind::SourceHash,
                ChangeKind::Lockfile("nix/packages/shellfirm/Cargo.lock".to_owned()),
            ]
        );

        let schema = target_spec(Target::ClaudeCodeSettingsSchema).expect("schema pin target spec");
        let schema_before = [state(
            "nix/pins/claude-code-settings-schema.json",
            br#"{"url":"https://old.invalid/schema","hash":"sha256-old"}"#,
        )];
        let schema_after = [state(
            "nix/pins/claude-code-settings-schema.json",
            br#"{"url":"https://new.invalid/schema","hash":"sha256-new"}"#,
        )];
        assert_eq!(
            diff_target(schema, &schema_before, &schema_after)
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [ChangeKind::Url, ChangeKind::SchemaHash]
        );

        let codex = target_spec(Target::CodexApp).expect("Codex app target spec");
        let codex_before = [state(
            "nix/pins/codex-app.json",
            br#"{"version":"1.0.0","url":"https://old.invalid/app.zip","hash":"sha256-old"}"#,
        )];
        let codex_after = [state(
            "nix/pins/codex-app.json",
            br#"{"version":"2.0.0","url":"https://new.invalid/app.zip","hash":"sha256-new"}"#,
        )];
        assert_eq!(
            diff_target(codex, &codex_before, &codex_after)
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [ChangeKind::Version, ChangeKind::Url, ChangeKind::AppHash]
        );
    }

    #[test]
    fn published_node_diff_attributes_pin_and_shared_input_to_difit() {
        let difit = target_spec(Target::Difit).expect("difit spec");
        let before = [
            state(
                "nix/pins/difit.json",
                br#"{"srcHash":"sha256-old","pnpmDepsHash":"sha256-old"}"#,
            ),
            state("flake.nix", br#"url = "github:yoshiko-pg/difit/v1.0.0";"#),
            state("flake.lock", br#"{"nodes":{"old":{}}}"#),
        ];
        let after = [
            state(
                "nix/pins/difit.json",
                br#"{"srcHash":"sha256-new","pnpmDepsHash":"sha256-new"}"#,
            ),
            state("flake.nix", br#"url = "github:yoshiko-pg/difit/v2.0.0";"#),
            state("flake.lock", br#"{"nodes":{"new":{}}}"#),
        ];
        let changes = diff_target(difit, &before, &after);
        assert!(changes.iter().all(|change| change.target == Target::Difit));
        assert_eq!(
            changes
                .into_iter()
                .map(|change| change.kind)
                .collect::<Vec<_>>(),
            [
                ChangeKind::Version,
                ChangeKind::SourceHash,
                ChangeKind::DependencyHash,
                ChangeKind::FlakeInput("difit-src".into()),
            ]
        );
    }

    #[test]
    fn renderer_redacts_hashes_urls_and_unsafe_text() {
        let secret_hash = "sha256-secret-value";
        let secret_url = "https://user:password@example.invalid/app.zip?token=secret";
        let mut ledger = Ledger::default();
        ledger.extend([
            Change {
                target: Target::CodexApp,
                kind: ChangeKind::Version,
                old: DisplayValue::Text("1.0.0\nforged: true".into()),
                new: DisplayValue::Text("2.0.0".into()),
            },
            Change {
                target: Target::CodexApp,
                kind: ChangeKind::Url,
                old: DisplayValue::Text(secret_url.into()),
                new: DisplayValue::Redacted,
            },
            Change {
                target: Target::CodexApp,
                kind: ChangeKind::AppHash,
                old: DisplayValue::Text(secret_hash.into()),
                new: DisplayValue::Redacted,
            },
        ]);

        let rendered = ledger.applied().render().expect("report");
        assert!(!rendered.contains(secret_hash));
        assert!(!rendered.contains(secret_url));
        assert!(!rendered.contains("forged: true"));
        assert!(rendered.contains("version: changed"));
        assert!(rendered.contains("URL: changed"));
        assert!(rendered.contains("app hash: changed"));
    }
}
