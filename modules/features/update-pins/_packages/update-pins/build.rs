use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

fn main() {
    println!("cargo:rerun-if-env-changed=UPDATE_PINS_REGISTRY_ROOT");
    let registry_root = env::var_os("UPDATE_PINS_REGISTRY_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(local_features_root);
    println!("cargo:rerun-if-changed={}", registry_root.display());
    let mut manifests = Vec::new();
    discover_registry_files(&registry_root, &mut manifests);
    manifests.sort();
    assert!(
        !manifests.is_empty(),
        "no Feature-owned update-pin.json manifests found below {}",
        registry_root.display()
    );
    let protocol_path = registry_root.join("update-pins/_data/registry-protocol.json");
    assert!(
        protocol_path.is_file(),
        "missing update-pins registry protocol at {}",
        protocol_path.display()
    );
    println!("cargo:rerun-if-changed={}", protocol_path.display());
    let protocol_raw = fs::read_to_string(&protocol_path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", protocol_path.display()));
    let protocol: Value = serde_json::from_str(&protocol_raw)
        .unwrap_or_else(|error| panic!("invalid {}: {error}", protocol_path.display()));
    let protocol = validate_protocol(&protocol, &protocol_path);

    let mut entries = manifests
        .iter()
        .map(|path| {
            println!("cargo:rerun-if-changed={}", path.display());
            let raw = fs::read_to_string(path)
                .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
            let value: Value = serde_json::from_str(&raw)
                .unwrap_or_else(|error| panic!("invalid {}: {error}", path.display()));
            (path.clone(), value)
        })
        .collect::<Vec<_>>();
    let target_order = protocol_targets(
        field(protocol, "targetOrder", &protocol_path),
        &protocol_path,
    );
    entries.sort_by_key(|(path, value)| {
        let name = string(field(object(value, path), "name", path), "name", path);
        target_order
            .iter()
            .position(|(candidate, _)| *candidate == name)
    });
    let ordered_names = entries
        .iter()
        .map(|(path, value)| string(field(object(value, path), "name", path), "name", path))
        .collect::<Vec<_>>();
    assert_eq!(
        ordered_names,
        target_order
            .iter()
            .map(|(name, _)| *name)
            .collect::<Vec<_>>(),
        "owner manifests do not match targetOrder in {}",
        protocol_path.display()
    );
    for pair in ordered_names.windows(2) {
        assert_ne!(pair[0], pair[1], "duplicate update-pin name {}", pair[0]);
    }

    let rendered = entries
        .iter()
        .zip(&target_order)
        .map(|((path, value), (_, target))| {
            render_target(value, path, target, protocol, &protocol_path)
        })
        .collect::<Vec<_>>()
        .join("\n");
    let output = format!("pub static TARGET_SPECS: &[TargetSpec] = &[\n{rendered}];\n");
    let output_path =
        PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR")).join("target_specs.rs");
    fs::write(&output_path, output)
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", output_path.display()));
}

fn local_features_root() -> PathBuf {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    manifest_dir
        .ancestors()
        .find(|candidate| {
            candidate
                .join("update-pins/_data/registry-protocol.json")
                .is_file()
        })
        .expect("could not locate the modules/features registry root")
        .to_path_buf()
}

fn discover_registry_files(directory: &Path, manifests: &mut Vec<PathBuf>) {
    let entries = fs::read_dir(directory)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", directory.display()));
    for entry in entries {
        let entry = entry.unwrap_or_else(|error| {
            panic!(
                "failed to read an entry below {}: {error}",
                directory.display()
            )
        });
        let path = entry.path();
        let file_type = entry
            .file_type()
            .unwrap_or_else(|error| panic!("failed to inspect {}: {error}", path.display()));
        if file_type.is_dir() {
            discover_registry_files(&path, manifests);
        } else if file_type.is_file()
            && entry.file_name() == "update-pin.json"
            && path
                .parent()
                .and_then(Path::file_name)
                .is_some_and(|name| name == "_interface")
        {
            manifests.push(path);
        }
    }
}

fn validate_protocol<'a>(value: &'a Value, path: &Path) -> &'a Map<String, Value> {
    let protocol = object(value, path);
    exact_fields(
        protocol,
        &["flakeFile", "schemaVersion", "targetOrder"],
        path,
    );
    assert_eq!(
        integer(
            field(protocol, "schemaVersion", path),
            "schemaVersion",
            path
        ),
        1,
        "unsupported registry protocol in {}",
        path.display()
    );
    let flake_file = object(field(protocol, "flakeFile", path), path);
    exact_fields(
        flake_file,
        &["generatedPath", "generator", "lockPath"],
        path,
    );
    let target_order = protocol_targets(field(protocol, "targetOrder", path), path);
    assert!(
        !target_order.is_empty(),
        "targetOrder is empty in {}",
        path.display()
    );
    let unique_names = target_order
        .iter()
        .map(|(name, _)| *name)
        .collect::<BTreeSet<_>>();
    assert_eq!(
        unique_names.len(),
        target_order.len(),
        "targetOrder contains duplicate names in {}",
        path.display()
    );
    let unique_targets = target_order
        .iter()
        .map(|(_, target)| *target)
        .collect::<BTreeSet<_>>();
    assert_eq!(
        unique_targets.len(),
        target_order.len(),
        "targetOrder contains duplicate handlers in {}",
        path.display()
    );
    protocol
}

fn managed_paths<'a>(
    kind: &'a Map<String, Value>,
    path: &Path,
    protocol: &'a Map<String, Value>,
    protocol_path: &Path,
) -> Vec<&'a str> {
    let kind_type = string(field(kind, "type", path), "kind.type", path);
    let pin = string(field(kind, "pin", path), "kind.pin", path);
    if matches!(kind_type, "paired-release" | "published-node-package") {
        let source = if kind_type == "paired-release" {
            field(kind, "source", path)
        } else {
            field(
                object(field(kind, "dependencies", path), path),
                "source",
                path,
            )
        };
        let authority = object(field(object(source, path), "authority", path), path);
        let flake_file = object(field(protocol, "flakeFile", protocol_path), protocol_path);
        vec![
            pin,
            string(
                field(authority, "sourcePath", path),
                "authority.sourcePath",
                path,
            ),
            string(
                field(flake_file, "generatedPath", protocol_path),
                "flakeFile.generatedPath",
                protocol_path,
            ),
            string(
                field(flake_file, "lockPath", protocol_path),
                "flakeFile.lockPath",
                protocol_path,
            ),
        ]
    } else if kind_type == "shellfirm" {
        vec![
            pin,
            string(field(kind, "lock", path), "kind.lock", path),
            string(
                field(kind, "guardManifest", path),
                "kind.guardManifest",
                path,
            ),
            string(field(kind, "guardLock", path), "kind.guardLock", path),
        ]
    } else {
        vec![pin]
    }
}

fn render_target(
    value: &Value,
    path: &Path,
    target: &str,
    protocol: &Map<String, Value>,
    protocol_path: &Path,
) -> String {
    let entry = object(value, path);
    exact_fields(entry, &["kind", "name"], path);
    let target = target_variant(target, protocol_path);
    let name = rust_string(string(field(entry, "name", path), "name", path));
    let kind_value = field(entry, "kind", path);
    let kind = render_kind(kind_value, path, protocol, protocol_path);
    let managed_paths = render_strings(&managed_paths(
        object(kind_value, path),
        path,
        protocol,
        protocol_path,
    ));
    format!(
        "    TargetSpec {{ target: Target::{target}, name: {name}, kind: {kind}, managed_paths: &{managed_paths} }},"
    )
}

fn render_kind(
    value: &Value,
    path: &Path,
    protocol: &Map<String, Value>,
    protocol_path: &Path,
) -> String {
    let kind = object(value, path);
    match string(field(kind, "type", path), "kind.type", path) {
        "paired-release" => {
            exact_fields(kind, &["pin", "source", "type"], path);
            format!(
                "TargetKind::PairedRelease {{ pin: {}, source: {} }}",
                rust_string(string(field(kind, "pin", path), "kind.pin", path)),
                render_source(field(kind, "source", path), path, protocol, protocol_path)
            )
        }
        "release" => {
            exact_fields(
                kind,
                &["assetNaming", "pin", "repository", "sourceHash", "type"],
                path,
            );
            let asset_naming =
                match string(field(kind, "assetNaming", path), "kind.assetNaming", path) {
                    "name-field" => "AssetNaming::NameField",
                    "watchexec-target" => "AssetNaming::WatchexecTarget",
                    other => panic!("unsupported asset naming {other:?} in {}", path.display()),
                };
            format!(
                "TargetKind::Release {{ repository: {}, pin: {}, asset_naming: {asset_naming}, source_hash: {} }}",
                rust_string(string(
                    field(kind, "repository", path),
                    "kind.repository",
                    path
                )),
                rust_string(string(field(kind, "pin", path), "kind.pin", path)),
                boolean(field(kind, "sourceHash", path), "kind.sourceHash", path)
            )
        }
        "url-hash" => {
            exact_fields(kind, &["pin", "type"], path);
            format!(
                "TargetKind::UrlHash {{ pin: {} }}",
                rust_string(string(field(kind, "pin", path), "kind.pin", path))
            )
        }
        "shellfirm" => {
            exact_fields(
                kind,
                &[
                    "guardLock",
                    "guardManifest",
                    "lock",
                    "package",
                    "pin",
                    "repository",
                    "type",
                ],
                path,
            );
            format!(
                "TargetKind::Shellfirm {{ repository: {}, pin: {}, lock: {}, guard_manifest: {}, guard_lock: {}, package: {} }}",
                rust_string(string(
                    field(kind, "repository", path),
                    "kind.repository",
                    path
                )),
                rust_string(string(field(kind, "pin", path), "kind.pin", path)),
                rust_string(string(field(kind, "lock", path), "kind.lock", path)),
                rust_string(string(
                    field(kind, "guardManifest", path),
                    "kind.guardManifest",
                    path
                )),
                rust_string(string(
                    field(kind, "guardLock", path),
                    "kind.guardLock",
                    path
                )),
                rust_string(string(field(kind, "package", path), "kind.package", path))
            )
        }
        "published-node-package" => {
            exact_fields(
                kind,
                &["artifact", "build", "dependencies", "pin", "type"],
                path,
            );
            format!(
                "TargetKind::PublishedNodePackage(PublishedNodePackageSpec {{ pin: {}, artifact: {}, dependencies: {}, build: {} }})",
                rust_string(string(field(kind, "pin", path), "kind.pin", path)),
                render_artifact(field(kind, "artifact", path), path),
                render_dependencies(
                    field(kind, "dependencies", path),
                    path,
                    protocol,
                    protocol_path
                ),
                render_build(field(kind, "build", path), path)
            )
        }
        "codex-app" => {
            exact_fields(kind, &["pin", "type"], path);
            format!(
                "TargetKind::CodexApp {{ pin: {} }}",
                rust_string(string(field(kind, "pin", path), "kind.pin", path))
            )
        }
        other => panic!("unsupported target kind {other:?} in {}", path.display()),
    }
}

fn render_source(
    value: &Value,
    path: &Path,
    protocol: &Map<String, Value>,
    protocol_path: &Path,
) -> String {
    let source = object(value, path);
    exact_fields(source, &["authority", "input", "repository"], path);
    format!(
        "PairedSource {{ repository: {}, input: {}, authority: {} }}",
        rust_string(string(
            field(source, "repository", path),
            "source.repository",
            path
        )),
        rust_string(string(field(source, "input", path), "source.input", path)),
        render_authority(
            field(source, "authority", path),
            path,
            protocol,
            protocol_path
        )
    )
}

fn render_authority(
    value: &Value,
    path: &Path,
    protocol: &Map<String, Value>,
    protocol_path: &Path,
) -> String {
    let authority = object(value, path);
    exact_fields(authority, &["sourcePath"], path);
    let flake_file = object(field(protocol, "flakeFile", protocol_path), protocol_path);
    let generator = format!(
        "Some({})",
        render_generator(field(flake_file, "generator", protocol_path), protocol_path)
    );
    format!(
        "InputAuthority {{ source_path: {}, generated_flake_path: {}, lock_path: {}, generator: {generator} }}",
        rust_string(string(
            field(authority, "sourcePath", path),
            "authority.sourcePath",
            path
        )),
        rust_string(string(
            field(flake_file, "generatedPath", protocol_path),
            "authority.generatedFlakePath",
            protocol_path
        )),
        rust_string(string(
            field(flake_file, "lockPath", protocol_path),
            "authority.lockPath",
            protocol_path
        ))
    )
}

fn render_generator(value: &Value, path: &Path) -> String {
    let generator = object(value, path);
    exact_fields(generator, &["args", "baseline", "program"], path);
    let baseline = match field(generator, "baseline", path) {
        Value::Null => "None",
        value => match string(value, "generator.baseline", path) {
            "flake-file-check" => "Some(GeneratorBaseline::FlakeFileCheck)",
            other => panic!(
                "unsupported generator baseline {other:?} in {}",
                path.display()
            ),
        },
    };
    format!(
        "GeneratorCommand {{ program: {}, args: &{}, baseline: {baseline} }}",
        rust_string(string(
            field(generator, "program", path),
            "generator.program",
            path
        )),
        render_string_slice(field(generator, "args", path), "generator.args", path)
    )
}

fn render_artifact(value: &Value, path: &Path) -> String {
    let artifact = object(value, path);
    exact_fields(artifact, &["package", "sourceHashField", "type"], path);
    assert_eq!(
        string(field(artifact, "type", path), "artifact.type", path),
        "npm-registry-tarball",
        "unsupported published artifact in {}",
        path.display()
    );
    format!(
        "PublishedArtifact::NpmRegistryTarball {{ package: {}, source_hash_field: {} }}",
        rust_string(string(
            field(artifact, "package", path),
            "artifact.package",
            path
        )),
        rust_string(string(
            field(artifact, "sourceHashField", path),
            "artifact.sourceHashField",
            path
        ))
    )
}

fn render_dependencies(
    value: &Value,
    path: &Path,
    protocol: &Map<String, Value>,
    protocol_path: &Path,
) -> String {
    let dependencies = object(value, path);
    exact_fields(
        dependencies,
        &[
            "lockPath",
            "pnpmMajor",
            "scope",
            "source",
            "type",
            "workspace",
            "workspacePath",
        ],
        path,
    );
    assert_eq!(
        string(field(dependencies, "type", path), "dependencies.type", path),
        "upstream-pnpm",
        "unsupported dependency provenance in {}",
        path.display()
    );
    assert_eq!(
        integer(
            field(dependencies, "pnpmMajor", path),
            "dependencies.pnpmMajor",
            path
        ),
        11,
        "unsupported pnpm major in {}",
        path.display()
    );
    assert_eq!(
        string(
            field(dependencies, "scope", path),
            "dependencies.scope",
            path
        ),
        "production",
        "unsupported dependency scope in {}",
        path.display()
    );
    format!(
        "DependencyProvenance::UpstreamPnpm {{ source: {}, lock_path: {}, workspace_path: {}, workspace: {}, pnpm: PnpmMajor::V11, scope: DependencyScope::Production }}",
        render_source(
            field(dependencies, "source", path),
            path,
            protocol,
            protocol_path
        ),
        rust_string(string(
            field(dependencies, "lockPath", path),
            "dependencies.lockPath",
            path
        )),
        rust_string(string(
            field(dependencies, "workspacePath", path),
            "dependencies.workspacePath",
            path
        )),
        rust_string(string(
            field(dependencies, "workspace", path),
            "dependencies.workspace",
            path
        ))
    )
}

fn render_build(value: &Value, path: &Path) -> String {
    let build = object(value, path);
    exact_fields(
        build,
        &["dependencyHashField", "packageAttr", "pinOverride"],
        path,
    );
    format!(
        "PackageBuildSpec {{ package_attr: {}, pin_override: {}, dependency_hash_field: {} }}",
        rust_string(string(
            field(build, "packageAttr", path),
            "build.packageAttr",
            path
        )),
        rust_string(string(
            field(build, "pinOverride", path),
            "build.pinOverride",
            path
        )),
        rust_string(string(
            field(build, "dependencyHashField", path),
            "build.dependencyHashField",
            path
        ))
    )
}

fn render_string_slice(value: &Value, field_name: &str, path: &Path) -> String {
    render_strings(&string_array(value, field_name, path))
}

fn render_strings(values: &[&str]) -> String {
    format!(
        "[{}]",
        values
            .iter()
            .map(|value| rust_string(value))
            .collect::<Vec<_>>()
            .join(", ")
    )
}

fn string_array<'a>(value: &'a Value, field_name: &str, path: &Path) -> Vec<&'a str> {
    value
        .as_array()
        .unwrap_or_else(|| panic!("{field_name} must be an array in {}", path.display()))
        .iter()
        .map(|value| string(value, field_name, path))
        .collect()
}

fn protocol_targets<'a>(value: &'a Value, path: &Path) -> Vec<(&'a str, &'a str)> {
    value
        .as_array()
        .unwrap_or_else(|| panic!("targetOrder must be an array in {}", path.display()))
        .iter()
        .map(|value| {
            let target = object(value, path);
            exact_fields(target, &["name", "target"], path);
            (
                string(field(target, "name", path), "targetOrder.name", path),
                string(field(target, "target", path), "targetOrder.target", path),
            )
        })
        .collect()
}

fn target_variant<'a>(value: &'a str, path: &Path) -> &'a str {
    match value {
        "Hcom"
        | "AgentSlack"
        | "AgentBrowser"
        | "Watchexec"
        | "Shellfirm"
        | "Herdr"
        | "Difit"
        | "ClaudeCodeSettingsSchema"
        | "CodexApp" => value,
        other => panic!("unsupported Target variant {other:?} in {}", path.display()),
    }
}

fn object<'a>(value: &'a Value, path: &Path) -> &'a Map<String, Value> {
    value
        .as_object()
        .unwrap_or_else(|| panic!("expected an object in {}", path.display()))
}

fn field<'a>(object: &'a Map<String, Value>, name: &str, path: &Path) -> &'a Value {
    object
        .get(name)
        .unwrap_or_else(|| panic!("missing field {name:?} in {}", path.display()))
}

fn string<'a>(value: &'a Value, name: &str, path: &Path) -> &'a str {
    value
        .as_str()
        .unwrap_or_else(|| panic!("{name} must be a string in {}", path.display()))
}

fn integer(value: &Value, name: &str, path: &Path) -> u64 {
    value.as_u64().unwrap_or_else(|| {
        panic!(
            "{name} must be a non-negative integer in {}",
            path.display()
        )
    })
}

fn boolean(value: &Value, name: &str, path: &Path) -> bool {
    value
        .as_bool()
        .unwrap_or_else(|| panic!("{name} must be a boolean in {}", path.display()))
}

fn exact_fields(object: &Map<String, Value>, expected: &[&str], path: &Path) {
    let mut actual = object.keys().map(String::as_str).collect::<Vec<_>>();
    let mut expected = expected.to_vec();
    actual.sort_unstable();
    expected.sort_unstable();
    assert_eq!(actual, expected, "unexpected fields in {}", path.display());
}

fn rust_string(value: &str) -> String {
    format!("{value:?}")
}
