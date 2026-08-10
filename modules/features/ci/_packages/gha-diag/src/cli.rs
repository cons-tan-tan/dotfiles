use crate::discovery::{DocumentKind, resolve_inputs};
use crate::language_server::{Client, MAX_LSP_MESSAGE_BYTES, inspect_node};
use crate::report::{
    BundleReproduction, CheckedFileEvidence, Diagnostic, ExperimentalFeaturePolicy, FileEvidence,
    Hardening, LANGUAGE_SERVER_BUNDLE, LanguageServer, LicenseEvidence, RegistryVerification,
    Report, Runtime, Severity, Tool, format_text, language_server_metadata, sanitize_log_text,
    sha256,
};
use std::collections::BTreeSet;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const DEFAULT_TIMEOUT_SECONDS: u64 = 30;
const MAX_TIMEOUT_SECONDS: u64 = 300;
const DEFAULT_MAX_OLD_SPACE_SIZE_MIB: u64 = 512;

const USAGE: &str = "Usage: gha-diag [OPTIONS] [FILE ...]\n\
       gha-diag features [OPTIONS]\n\n\
Batch diagnostics for workflows and action metadata using GitHub's official language server.\n\n\
When FILE is omitted, .github/workflows/*.yml|yaml and action.yml|yaml up to three directories deep are checked.\n\n\
Commands:\n  features                 Show the effective language server experimental features\n\n\
Options:\n  --format text|json       Output diagnostics or an evidence report (default: text)\n  \
--quiet                   In text mode, output diagnostics only\n  \
--verbose                 In text mode, include full execution evidence\n  \
--disable-experimental-feature NAME\n                           Disable one upstream experimental feature (repeatable)\n  \
--no-experimental-features\n                           Disable every upstream experimental feature\n  \
--fail-on SEVERITY        Fail on this severity or higher: error, warning, information, hint\n                           (default: error)\n  \
--node PATH               Node.js executable (default: GHA_DIAG_NODE or PATH)\n  \
--timeout SECONDS         Per-operation language server timeout (default: 30)\n  \
--max-memory MIB          V8 old-space limit for the language server (default: 512)\n  \
--allow-empty             Succeed when no GitHub Actions files are discovered\n  \
-h, --help                Show this help\n  \
-V, --version             Show gha-diag and language server versions";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Format {
    Text,
    Json,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CommandKind {
    Check,
    Features,
}

#[derive(Debug)]
struct Options {
    command: CommandKind,
    format: Format,
    node: Option<PathBuf>,
    timeout_seconds: u64,
    max_memory_mib: u64,
    allow_empty: bool,
    quiet: bool,
    verbose: bool,
    enable_all_experimental_features: bool,
    disabled_experimental_features: BTreeSet<String>,
    fail_on: Severity,
    check_only_options: BTreeSet<&'static str>,
    files: Vec<PathBuf>,
    help: bool,
    version: bool,
}

#[derive(Debug, Clone, Copy)]
struct CheckOutcome {
    exit_code: u8,
    blocking_diagnostics: usize,
}

pub fn run(arguments: impl IntoIterator<Item = OsString>) -> Result<u8, String> {
    let options = parse(arguments)?;
    verify_embedded_language_server()?;
    if options.help {
        println!("{USAGE}");
        return Ok(0);
    }
    if options.version {
        let metadata = language_server_metadata();
        println!(
            "gha-diag {VERSION}\n{} {}",
            metadata.package, metadata.version
        );
        return Ok(0);
    }
    validate_experimental_feature_options(&options)?;
    if options.command == CommandKind::Features {
        print_features(&options)?;
        return Ok(0);
    }

    let root = std::env::current_dir()
        .and_then(|path| path.canonicalize())
        .map_err(|error| format!("cannot resolve current directory: {error}"))?;
    let files = resolve_inputs(&root, &options.files)?;
    if files.is_empty() {
        let exit_code = if options.allow_empty { 0 } else { 2 };
        if options.format == Format::Json {
            println!("{}", empty_report(&options, exit_code)?);
        } else {
            if !options.quiet {
                print_empty_text(&options, exit_code);
            }
            if !options.allow_empty {
                eprintln!("gha-diag: no GitHub Actions files were discovered");
            }
        }
        return Ok(exit_code);
    }

    let temporary = tempfile::tempdir()
        .map_err(|error| format!("cannot create private temporary directory: {error}"))?;
    let bundle = temporary.path().join("actions-languageserver.cjs");
    fs::write(&bundle, LANGUAGE_SERVER_BUNDLE)
        .map_err(|error| format!("cannot materialize bundled language server: {error}"))?;
    let environment_node = std::env::var_os("GHA_DIAG_NODE").map(PathBuf::from);
    let requested_node = options.node.as_deref().or(environment_node.as_deref());
    let runtime = inspect_node(
        requested_node,
        temporary.path(),
        Duration::from_secs(options.timeout_seconds),
    )?;

    let mut client = Client::spawn(
        &runtime,
        &bundle,
        &root,
        temporary.path(),
        Duration::from_secs(options.timeout_seconds),
        options.max_memory_mib,
    )?;
    let disabled_experimental_features: Vec<_> = options
        .disabled_experimental_features
        .iter()
        .cloned()
        .collect();
    client.initialize(
        options.enable_all_experimental_features,
        &disabled_experimental_features,
    )?;

    let mut diagnostics = Vec::new();
    let mut evidence = Vec::with_capacity(files.len());
    for input in &files {
        let file = &input.path;
        let bytes = fs::read(file).map_err(|error| {
            format!(
                "cannot read GitHub Actions file {}: {error}",
                file.display()
            )
        })?;
        let text = std::str::from_utf8(&bytes)
            .map_err(|_| format!("GitHub Actions file is not valid UTF-8: {}", file.display()))?;
        evidence.push(CheckedFileEvidence {
            path: file
                .strip_prefix(&root)
                .unwrap_or(file)
                .to_string_lossy()
                .replace('\\', "/"),
            sha256: sha256(&bytes),
            kind: input.kind,
        });
        diagnostics.extend(client.diagnose(file, text)?);
    }
    client.shutdown()?;
    let mut read_dependencies = client.read_dependencies();
    read_dependencies
        .retain(|dependency| !evidence.iter().any(|file| file.path == dependency.path));
    diagnostics.sort_by(|left, right| {
        left.file
            .cmp(&right.file)
            .then(left.line.cmp(&right.line))
            .then(left.column.cmp(&right.column))
            .then(left.severity.cmp(&right.severity))
            .then(left.message.cmp(&right.message))
    });
    diagnostics.dedup();
    let blocking_diagnostics = diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.severity <= options.fail_on)
        .count();
    let outcome = CheckOutcome {
        exit_code: if blocking_diagnostics > 0 { 1 } else { 0 },
        blocking_diagnostics,
    };

    if options.format == Format::Json {
        let report = build_report(
            evidence,
            read_dependencies,
            diagnostics.clone(),
            &runtime.executable,
            runtime.version,
            runtime.permission_model_restricts_network,
            options.timeout_seconds,
            options.max_memory_mib,
            outcome,
            &options,
        );
        println!(
            "{}",
            serde_json::to_string_pretty(&report)
                .map_err(|error| format!("cannot serialize report: {error}"))?
        );
    } else {
        print_text_report(
            &evidence,
            &read_dependencies,
            &diagnostics,
            &runtime.version,
            runtime.permission_model_restricts_network,
            outcome,
            &options,
        );
    }
    Ok(outcome.exit_code)
}

fn print_empty_text(options: &Options, exit_code: u8) {
    println!("Checked GitHub Actions files:");
    println!("  (none)");
    println!();
    if options.verbose {
        print_execution_evidence(options, None, false);
    } else {
        print_validator_summary(options, false);
    }
    println!(
        "Result: {} (exit_code={exit_code}, blocking_diagnostics=0)",
        text_conclusion(exit_code)
    );
    if options.verbose {
        println!(
            "Summary: files=0 workflows=0 actions=0 passed=0 failed=0 with_diagnostics=0 diagnostics=0 errors=0 warnings=0 information=0 hints=0 dependencies=0"
        );
    } else {
        println!("Summary: files=0 workflows=0 actions=0 diagnostics=0");
    }
}

fn print_text_report(
    files: &[CheckedFileEvidence],
    read_dependencies: &[FileEvidence],
    diagnostics: &[Diagnostic],
    node_version: &str,
    network_restricted: bool,
    outcome: CheckOutcome,
    options: &Options,
) {
    if options.quiet {
        for diagnostic in diagnostics {
            println!("{}", format_text(diagnostic));
        }
        return;
    }

    println!("Checked GitHub Actions files:");

    let mut passed = 0;
    let mut failed = 0;
    let mut with_diagnostics = 0;
    for file in files {
        let file_diagnostics: Vec<_> = diagnostics
            .iter()
            .filter(|diagnostic| diagnostic.file == file.path)
            .collect();
        if file_diagnostics.is_empty() {
            passed += 1;
            println!(
                "  [PASS] [{}] {}",
                file.kind.as_str(),
                sanitize_log_text(&file.path)
            );
        } else {
            with_diagnostics += 1;
            let blocking = file_diagnostics
                .iter()
                .filter(|diagnostic| diagnostic.severity <= options.fail_on)
                .count();
            let status = if blocking == 0 {
                passed += 1;
                "PASS+DIAGNOSTICS"
            } else {
                failed += 1;
                "FAIL"
            };
            println!(
                "  [{status}] [{}] {} diagnostics={} blocking={blocking}",
                file.kind.as_str(),
                sanitize_log_text(&file.path),
                file_diagnostics.len()
            );
            for diagnostic in file_diagnostics {
                println!("    {}", format_text(diagnostic));
            }
        }
    }

    if options.verbose && !read_dependencies.is_empty() {
        println!();
        println!("Read dependencies:");
        for dependency in read_dependencies {
            println!("  [READ] {}", sanitize_log_text(&dependency.path));
        }
    }

    let mut errors = 0;
    let mut warnings = 0;
    let mut information = 0;
    let mut hints = 0;
    for diagnostic in diagnostics {
        match diagnostic.severity {
            Severity::Error => errors += 1,
            Severity::Warning => warnings += 1,
            Severity::Information => information += 1,
            Severity::Hint => hints += 1,
        }
    }
    let workflows = files
        .iter()
        .filter(|file| file.kind == DocumentKind::Workflow)
        .count();
    let actions = files.len() - workflows;
    println!();
    if options.verbose {
        print_execution_evidence(options, Some(node_version), network_restricted);
    } else {
        print_validator_summary(options, true);
    }
    println!(
        "Result: {} (exit_code={}, blocking_diagnostics={})",
        text_conclusion(outcome.exit_code),
        outcome.exit_code,
        outcome.blocking_diagnostics
    );
    if options.verbose {
        println!(
            "Summary: files={} workflows={workflows} actions={actions} passed={passed} failed={failed} with_diagnostics={with_diagnostics} diagnostics={} errors={errors} warnings={warnings} information={information} hints={hints} dependencies={}",
            files.len(),
            diagnostics.len(),
            read_dependencies.len()
        );
    } else {
        println!(
            "Summary: files={} workflows={workflows} actions={actions} diagnostics={}",
            files.len(),
            diagnostics.len()
        );
    }
}

fn print_validator_summary(options: &Options, executed: bool) {
    let metadata = language_server_metadata();
    let execution = if executed { "" } else { "; status=not-started" };
    println!(
        "Validator: {} {} (experimental={}; fail-on={}{})",
        metadata.package,
        metadata.version,
        experimental_feature_policy_text(options),
        options.fail_on.as_str(),
        execution
    );
}

fn print_execution_evidence(
    options: &Options,
    node_version: Option<&str>,
    network_restricted: bool,
) {
    let metadata = language_server_metadata();
    println!("Execution evidence:");
    println!("  Tool: gha-diag {VERSION}");
    println!(
        "  Language server: {} {}",
        metadata.package, metadata.version
    );
    print_experimental_feature_evidence(options, "  ");
    println!("  Failure threshold: {}", options.fail_on.as_str());
    println!("  Empty input allowed: {}", options.allow_empty);
    match node_version {
        Some(version) => println!(
            "  Runtime: Node.js {} (permission_model=enabled, network_restricted={network_restricted})",
            sanitize_log_text(version)
        ),
        None => println!("  Runtime: not started (no files discovered)"),
    }
    println!();
}

fn text_conclusion(exit_code: u8) -> &'static str {
    if exit_code == 0 { "PASS" } else { "FAIL" }
}

fn report_conclusion(exit_code: u8) -> &'static str {
    if exit_code == 0 { "success" } else { "failure" }
}

fn experimental_feature_mode(options: &Options) -> &'static str {
    if options.enable_all_experimental_features {
        "all"
    } else {
        "none"
    }
}

fn experimental_feature_policy_text(options: &Options) -> String {
    let mode = experimental_feature_mode(options);
    let overrides = options.disabled_experimental_features.len();
    if overrides == 0 {
        return mode.to_owned();
    }
    let suffix = if overrides == 1 {
        "override"
    } else {
        "overrides"
    };
    format!("{mode} ({overrides} CLI {suffix})")
}

fn enabled_experimental_features(options: &Options) -> Vec<String> {
    if !options.enable_all_experimental_features {
        return Vec::new();
    }
    language_server_metadata()
        .experimental_features
        .iter()
        .filter(|feature| !options.disabled_experimental_features.contains(*feature))
        .cloned()
        .collect()
}

fn disabled_experimental_features(options: &Options) -> Vec<String> {
    if options.enable_all_experimental_features {
        options
            .disabled_experimental_features
            .iter()
            .cloned()
            .collect()
    } else {
        language_server_metadata().experimental_features.clone()
    }
}

fn validate_experimental_feature_options(options: &Options) -> Result<(), String> {
    if !options.enable_all_experimental_features
        && !options.disabled_experimental_features.is_empty()
    {
        return Err(
            "--disable-experimental-feature cannot be combined with --no-experimental-features"
                .to_owned(),
        );
    }
    let available: BTreeSet<_> = language_server_metadata()
        .experimental_features
        .iter()
        .map(String::as_str)
        .collect();
    let unknown: Vec<_> = options
        .disabled_experimental_features
        .iter()
        .filter(|feature| !available.contains(feature.as_str()))
        .cloned()
        .collect();
    if unknown.is_empty() {
        return Ok(());
    }
    Err(format!(
        "unknown experimental feature(s): {}; available features: {}",
        unknown.join(", "),
        language_server_metadata().experimental_features.join(", ")
    ))
}

fn print_experimental_feature_evidence(options: &Options, prefix: &str) {
    println!(
        "{prefix}Experimental features: {}",
        experimental_feature_policy_text(options)
    );
    let enabled: BTreeSet<_> = enabled_experimental_features(options).into_iter().collect();
    for feature in &language_server_metadata().experimental_features {
        let status = if enabled.contains(feature) {
            "enabled "
        } else {
            "disabled"
        };
        let override_note = if options.disabled_experimental_features.contains(feature) {
            " (CLI override)"
        } else {
            ""
        };
        println!("{prefix}  [{status}] {feature}{override_note}");
    }
}

fn print_features(options: &Options) -> Result<(), String> {
    let metadata = language_server_metadata();
    let enabled: BTreeSet<_> = enabled_experimental_features(options).into_iter().collect();
    if options.format == Format::Json {
        let features: Vec<_> = metadata
            .experimental_features
            .iter()
            .map(|feature| {
                serde_json::json!({
                    "name": feature,
                    "enabled": enabled.contains(feature),
                    "overridden": options.disabled_experimental_features.contains(feature)
                })
            })
            .collect();
        let report = serde_json::json!({
            "schemaVersion": "gha-diag-features-v1",
            "languageServer": {
                "package": metadata.package,
                "version": metadata.version,
                "gitHead": metadata.git_head
            },
            "policy": experimental_feature_mode(options),
            "features": features
        });
        println!(
            "{}",
            serde_json::to_string_pretty(&report)
                .map_err(|error| format!("cannot serialize feature report: {error}"))?
        );
    } else {
        println!("Language server experimental features:");
        println!("  Policy: {}", experimental_feature_policy_text(options));
        for feature in &metadata.experimental_features {
            let status = if enabled.contains(feature) {
                "enabled "
            } else {
                "disabled"
            };
            let override_note = if options.disabled_experimental_features.contains(feature) {
                " (CLI override)"
            } else {
                ""
            };
            println!("  [{status}] {feature}{override_note}");
        }
        println!();
        println!("Language server: {} {}", metadata.package, metadata.version);
    }
    Ok(())
}

fn empty_report(options: &Options, exit_code: u8) -> Result<String, String> {
    let metadata = language_server_metadata();
    let enabled_features = enabled_experimental_features(options);
    let disabled_features = disabled_experimental_features(options);
    let report = serde_json::json!({
        "schemaVersion": "gha-diag-report-v1",
        "tool": { "name": "gha-diag", "version": VERSION },
        "languageServer": {
            "package": metadata.package,
            "version": metadata.version,
            "source": "bundled-release",
            "integrity": metadata.integrity,
            "gitHead": metadata.git_head,
            "publishedAt": metadata.published_at,
            "attestation": metadata.attestation,
            "provenancePredicateType": metadata.provenance_predicate_type,
            "registrySignatureKeyId": metadata.registry_signature_key_id,
            "upstreamPackageLockSha256": metadata.upstream_package_lock_sha256,
            "registryVerification": {
                "sourceDependencies": metadata.registry_verification.source_dependencies,
                "reproductionDependencies": metadata.registry_verification.reproduction_dependencies
            },
            "bundleReproduction": {
                "byteForByte": metadata.bundle_reproduction.byte_for_byte,
                "esbuildVersion": metadata.bundle_reproduction.esbuild_version
            },
            "bundleSha256": sha256(LANGUAGE_SERVER_BUNDLE),
            "licenseEvidence": {
                "nodeNoticeSha256": metadata.node_licenses_sha256,
                "nodeInventorySha256": metadata.node_licenses_inventory_sha256
            },
            "positionEncoding": "utf-16",
            "experimentalFeatures": enabled_features,
            "experimentalFeaturePolicy": {
                "mode": experimental_feature_mode(options),
                "available": metadata.experimental_features,
                "disabled": disabled_features
            }
        },
        "runtime": null,
        "hardening": null,
        "failureThreshold": options.fail_on,
        "emptyInputAllowed": options.allow_empty,
        "conclusion": report_conclusion(exit_code),
        "exitCode": exit_code,
        "blockingDiagnostics": 0,
        "files": [],
        "readDependencies": [],
        "diagnostics": [],
        "limitations": [
            "No GitHub Actions files were discovered, so the language server was not executed."
        ]
    });
    serde_json::to_string_pretty(&report)
        .map_err(|error| format!("cannot serialize report: {error}"))
}

fn verify_embedded_language_server() -> Result<(), String> {
    let metadata = language_server_metadata();
    if metadata
        .experimental_features
        .windows(2)
        .any(|features| features[0] >= features[1])
        || metadata
            .experimental_features
            .iter()
            .any(|feature| !valid_experimental_feature_name(feature))
    {
        return Err(
            "language-server.json contains an invalid experimental feature inventory".to_owned(),
        );
    }
    let actual = sha256(LANGUAGE_SERVER_BUNDLE);
    if actual != metadata.bundle_sha256 {
        return Err(format!(
            "bundled language server hash does not match language-server.json: expected {}, got {actual}",
            metadata.bundle_sha256
        ));
    }
    Ok(())
}

fn valid_experimental_feature_name(feature: &str) -> bool {
    let mut bytes = feature.bytes();
    let Some(first) = bytes.next() else {
        return false;
    };
    feature.len() <= 128
        && first.is_ascii_alphabetic()
        && bytes.all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

#[allow(clippy::too_many_arguments)]
fn build_report(
    files: Vec<CheckedFileEvidence>,
    read_dependencies: Vec<FileEvidence>,
    diagnostics: Vec<crate::report::Diagnostic>,
    executable: &Path,
    node_version: String,
    network_restricted: bool,
    timeout_seconds: u64,
    max_memory_mib: u64,
    outcome: CheckOutcome,
    options: &Options,
) -> Report {
    let metadata = language_server_metadata();
    Report {
        schema_version: "gha-diag-report-v1",
        tool: Tool {
            name: "gha-diag",
            version: VERSION,
        },
        language_server: LanguageServer {
            package: &metadata.package,
            version: &metadata.version,
            source: "bundled-release",
            integrity: &metadata.integrity,
            git_head: &metadata.git_head,
            published_at: &metadata.published_at,
            attestation: &metadata.attestation,
            provenance_predicate_type: &metadata.provenance_predicate_type,
            registry_signature_key_id: &metadata.registry_signature_key_id,
            upstream_package_lock_sha256: &metadata.upstream_package_lock_sha256,
            registry_verification: RegistryVerification {
                source_dependencies: metadata.registry_verification.source_dependencies,
                reproduction_dependencies: metadata.registry_verification.reproduction_dependencies,
            },
            bundle_reproduction: BundleReproduction {
                byte_for_byte: metadata.bundle_reproduction.byte_for_byte,
                esbuild_version: &metadata.bundle_reproduction.esbuild_version,
            },
            bundle_sha256: sha256(LANGUAGE_SERVER_BUNDLE),
            license_evidence: LicenseEvidence {
                node_notice_sha256: &metadata.node_licenses_sha256,
                node_inventory_sha256: &metadata.node_licenses_inventory_sha256,
            },
            position_encoding: "utf-16",
            experimental_features: enabled_experimental_features(options),
            experimental_feature_policy: ExperimentalFeaturePolicy {
                mode: experimental_feature_mode(options),
                available: metadata.experimental_features.clone(),
                disabled: disabled_experimental_features(options),
            },
        },
        runtime: Runtime {
            implementation: "node",
            version: node_version,
            executable: executable.to_string_lossy().into_owned(),
        },
        hardening: Hardening {
            environment_allowlist: true,
            synthetic_home: true,
            node_permission_model: true,
            node_permission_model_restricts_network: network_restricted,
            lsp_operation_timeout_seconds: timeout_seconds,
            max_old_space_size_mib: max_memory_mib,
            max_lsp_message_bytes: MAX_LSP_MESSAGE_BYTES,
        },
        failure_threshold: options.fail_on,
        empty_input_allowed: options.allow_empty,
        conclusion: report_conclusion(outcome.exit_code),
        exit_code: outcome.exit_code,
        blocking_diagnostics: outcome.blocking_diagnostics,
        files,
        read_dependencies,
        diagnostics,
        limitations: vec![
            "This report records static diagnostics from the bundled GitHub Actions language server; it does not prove that a workflow or action will run successfully.",
            "Runner images, shell commands, remote actions, permissions, secrets, and external services are not fully validated.",
            "Node.js Permission Model is defense in depth and is not a security boundary for malicious code.",
        ],
    }
}

fn parse(arguments: impl IntoIterator<Item = OsString>) -> Result<Options, String> {
    let mut options = Options {
        command: CommandKind::Check,
        format: Format::Text,
        node: None,
        timeout_seconds: DEFAULT_TIMEOUT_SECONDS,
        max_memory_mib: DEFAULT_MAX_OLD_SPACE_SIZE_MIB,
        allow_empty: false,
        quiet: false,
        verbose: false,
        enable_all_experimental_features: true,
        disabled_experimental_features: BTreeSet::new(),
        fail_on: Severity::Error,
        check_only_options: BTreeSet::new(),
        files: Vec::new(),
        help: false,
        version: false,
    };
    let arguments: Vec<_> = arguments.into_iter().collect();
    let mut index = 0;
    let mut positional_only = false;
    while index < arguments.len() {
        let value = &arguments[index];
        let text = value
            .to_str()
            .ok_or_else(|| "arguments must be valid UTF-8".to_owned())?;
        if positional_only {
            options.files.push(PathBuf::from(value));
        } else {
            match text {
                "--" => positional_only = true,
                "-h" | "--help" => options.help = true,
                "-V" | "--version" => options.version = true,
                "--allow-empty" => {
                    options.allow_empty = true;
                    options.check_only_options.insert("--allow-empty");
                }
                "--quiet" => {
                    options.quiet = true;
                    options.check_only_options.insert("--quiet");
                }
                "--verbose" => {
                    options.verbose = true;
                    options.check_only_options.insert("--verbose");
                }
                "--no-experimental-features" => {
                    options.enable_all_experimental_features = false;
                }
                "--disable-experimental-feature" => {
                    index += 1;
                    let feature = arguments
                        .get(index)
                        .and_then(|value| value.to_str())
                        .ok_or_else(|| "--disable-experimental-feature requires NAME".to_owned())?;
                    options
                        .disabled_experimental_features
                        .insert(feature.to_owned());
                }
                "--fail-on" => {
                    options.check_only_options.insert("--fail-on");
                    index += 1;
                    let severity = arguments
                        .get(index)
                        .and_then(|value| value.to_str())
                        .ok_or_else(|| "--fail-on requires SEVERITY".to_owned())?;
                    options.fail_on = match severity {
                        "error" => Severity::Error,
                        "warning" => Severity::Warning,
                        "information" => Severity::Information,
                        "hint" => Severity::Hint,
                        _ => {
                            return Err(
                                "--fail-on must be error, warning, information, or hint".to_owned()
                            );
                        }
                    };
                }
                "--format" => {
                    index += 1;
                    let format = arguments
                        .get(index)
                        .and_then(|value| value.to_str())
                        .ok_or_else(|| "--format requires text or json".to_owned())?;
                    options.format = match format {
                        "text" => Format::Text,
                        "json" => Format::Json,
                        _ => return Err("--format must be either text or json".to_owned()),
                    };
                }
                "--node" => {
                    options.check_only_options.insert("--node");
                    index += 1;
                    options.node = Some(PathBuf::from(
                        arguments
                            .get(index)
                            .ok_or_else(|| "--node requires PATH".to_owned())?,
                    ));
                }
                "--timeout" => {
                    options.check_only_options.insert("--timeout");
                    index += 1;
                    options.timeout_seconds = parse_positive(arguments.get(index), "--timeout")?;
                    if options.timeout_seconds > MAX_TIMEOUT_SECONDS {
                        return Err(format!(
                            "--timeout must not exceed {MAX_TIMEOUT_SECONDS} seconds"
                        ));
                    }
                }
                "--max-memory" => {
                    options.check_only_options.insert("--max-memory");
                    index += 1;
                    options.max_memory_mib = parse_positive(arguments.get(index), "--max-memory")?;
                }
                option if option.starts_with('-') => {
                    return Err(format!("unknown option: {option}"));
                }
                "features" if options.command == CommandKind::Check && options.files.is_empty() => {
                    options.command = CommandKind::Features;
                }
                _ if options.command == CommandKind::Features => {
                    return Err("features command does not accept FILE arguments".to_owned());
                }
                _ => options.files.push(PathBuf::from(value)),
            }
        }
        index += 1;
    }
    if options.quiet && options.format == Format::Json {
        return Err("--quiet cannot be combined with --format json".to_owned());
    }
    if options.verbose && options.format == Format::Json {
        return Err("--verbose cannot be combined with --format json".to_owned());
    }
    if options.quiet && options.verbose {
        return Err("--quiet cannot be combined with --verbose".to_owned());
    }
    if options.command == CommandKind::Features {
        if !options.files.is_empty() {
            return Err("features command does not accept FILE arguments".to_owned());
        }
        if !options.check_only_options.is_empty() {
            return Err(format!(
                "features command does not accept check-only option(s): {}",
                options
                    .check_only_options
                    .iter()
                    .copied()
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
    }
    Ok(options)
}

fn parse_positive(value: Option<&OsString>, option: &str) -> Result<u64, String> {
    let raw = value
        .and_then(|value| value.to_str())
        .ok_or_else(|| format!("{option} requires a positive integer"))?;
    let parsed = raw
        .parse::<u64>()
        .map_err(|_| format!("{option} requires a positive integer"))?;
    if parsed == 0 {
        return Err(format!("{option} requires a positive integer"));
    }
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_output_and_runtime_options() {
        let options = parse(
            [
                "--format",
                "json",
                "--node",
                "/opt/node",
                "--timeout",
                "10",
                "workflow.yaml",
            ]
            .into_iter()
            .map(OsString::from),
        )
        .expect("arguments");
        assert_eq!(options.format, Format::Json);
        assert_eq!(options.node, Some(PathBuf::from("/opt/node")));
        assert_eq!(options.timeout_seconds, 10);
        assert!(options.enable_all_experimental_features);
        assert_eq!(options.fail_on, Severity::Error);
        assert_eq!(options.files, [PathBuf::from("workflow.yaml")]);
    }

    #[test]
    fn parses_feature_command_overrides_and_thresholds() {
        let options = parse(
            [
                "features",
                "--format",
                "json",
                "--disable-experimental-feature",
                "allowBackgroundSteps",
            ]
            .into_iter()
            .map(OsString::from),
        )
        .expect("feature arguments");
        assert_eq!(options.command, CommandKind::Features);
        assert_eq!(options.format, Format::Json);
        assert!(
            options
                .disabled_experimental_features
                .contains("allowBackgroundSteps")
        );

        let check = parse(
            ["--fail-on", "warning", "workflow.yaml"]
                .into_iter()
                .map(OsString::from),
        )
        .expect("threshold arguments");
        assert_eq!(check.fail_on, Severity::Warning);
    }

    #[test]
    fn double_dash_preserves_a_file_named_features() {
        let options = parse(["--", "features"].into_iter().map(OsString::from))
            .expect("positional features file");
        assert_eq!(options.command, CommandKind::Check);
        assert_eq!(options.files, [PathBuf::from("features")]);
    }

    #[test]
    fn feature_command_rejects_explicit_check_only_arguments() {
        for arguments in [
            vec!["features", "--fail-on", "error"],
            vec!["features", "--timeout", "30"],
            vec!["features", "--max-memory", "512"],
            vec!["features", "--verbose"],
            vec!["features", "--", "ignored.yaml"],
        ] {
            let error = parse(arguments.into_iter().map(OsString::from))
                .expect_err("check-only argument must be rejected");
            assert!(error.contains("features command does not"));
        }
    }

    #[test]
    fn validates_safe_experimental_feature_names() {
        assert!(valid_experimental_feature_name("allow-feature_1.test"));
        assert!(!valid_experimental_feature_name(""));
        assert!(!valid_experimental_feature_name("1feature"));
        assert!(!valid_experimental_feature_name("feature\nname"));
    }

    #[test]
    fn rejects_unknown_options() {
        let error = parse([OsString::from("--wat")]).expect_err("unknown option");
        assert!(error.contains("unknown option"));
    }

    #[test]
    fn text_output_modes_reject_ambiguous_combinations() {
        let error = parse(
            ["--quiet", "--format", "json"]
                .into_iter()
                .map(OsString::from),
        )
        .expect_err("quiet JSON is ambiguous");
        assert!(error.contains("cannot be combined"));

        let error = parse(
            ["--verbose", "--format", "json"]
                .into_iter()
                .map(OsString::from),
        )
        .expect_err("verbose JSON is redundant");
        assert!(error.contains("cannot be combined"));

        let error = parse(["--quiet", "--verbose"].into_iter().map(OsString::from))
            .expect_err("quiet and verbose conflict");
        assert!(error.contains("cannot be combined"));
    }

    #[test]
    fn rejects_a_timeout_that_could_overflow_deadlines() {
        let error = parse(
            ["--timeout", "18446744073709551615"]
                .into_iter()
                .map(OsString::from),
        )
        .expect_err("timeout must be bounded");
        assert!(error.contains("must not exceed"));
    }
}
