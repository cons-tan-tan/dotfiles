use serde_json::Value;
use std::fs;
use std::process::Command;

fn node() -> String {
    std::env::var("GHA_DIAG_TEST_NODE").unwrap_or_else(|_| "node".to_owned())
}

fn language_server_version() -> String {
    let metadata: Value = serde_json::from_str(include_str!("../language-server.json"))
        .expect("language server metadata");
    metadata["version"]
        .as_str()
        .expect("language server version")
        .to_owned()
}

fn experimental_features() -> Vec<String> {
    let metadata: Value = serde_json::from_str(include_str!("../language-server.json"))
        .expect("language server metadata");
    metadata["experimentalFeatures"]
        .as_array()
        .expect("experimental feature inventory")
        .iter()
        .map(|feature| {
            feature
                .as_str()
                .expect("experimental feature name")
                .to_owned()
        })
        .collect()
}

#[test]
fn reports_versions_without_starting_node() {
    let output = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .arg("--version")
        .output()
        .expect("run gha-diag");
    assert!(output.status.success());
    let stdout = String::from_utf8(output.stdout).expect("UTF-8");
    assert!(stdout.contains(&format!("gha-diag {}", env!("CARGO_PKG_VERSION"))));
    assert!(stdout.contains(&format!(
        "@actions/languageserver {}",
        language_server_version()
    )));
}

#[test]
fn text_output_lists_checked_files_and_a_machine_readable_summary() {
    let repository = tempfile::tempdir().expect("repository");
    let workflows = repository.path().join(".github/workflows");
    fs::create_dir_all(&workflows).expect("workflow directory");
    fs::write(
        workflows.join("valid.yaml"),
        "on: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n",
    )
    .expect("valid workflow");
    fs::write(
        workflows.join("invalid.yaml"),
        "on: push\njobs:\n  build:\n    needs: missing\n    runs-on: ubuntu-latest\n",
    )
    .expect("invalid workflow");
    fs::write(
        repository.path().join("action.yml"),
        "name: Example action\ndescription: Test action discovery\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo ok\n",
    )
    .expect("valid action metadata");

    let output = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--node", &node()])
        .output()
        .expect("run gha-diag");
    assert_eq!(
        output.status.code(),
        Some(1),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8(output.stdout).expect("UTF-8 output");
    assert!(stdout.contains("Checked GitHub Actions files:"));
    assert!(stdout.contains("[PASS] [workflow] .github/workflows/valid.yaml"));
    assert!(stdout.contains("[PASS] [action] action.yml"));
    assert!(stdout.contains("[FAIL] [workflow] .github/workflows/invalid.yaml diagnostics="));
    assert!(!stdout.contains("Execution evidence:"));
    assert!(!stdout.contains("[enabled ]"));
    assert!(stdout.contains(&format!(
        "Validator: @actions/languageserver {} (experimental=all; fail-on=error)",
        language_server_version()
    )));
    assert!(stdout.contains("Result: FAIL (exit_code=1, blocking_diagnostics="));
    assert!(stdout.contains("Summary: files=3 workflows=2 actions=1 diagnostics="));
    let checked = stdout
        .find("Checked GitHub Actions files:")
        .expect("checked files heading");
    let validator = stdout.find("Validator:").expect("validator summary");
    let result = stdout.find("Result:").expect("result");
    let summary = stdout.rfind("Summary:").expect("summary");
    assert!(checked < validator);
    assert!(validator < result);
    assert!(result < summary);

    let verbose = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--node", &node(), "--verbose"])
        .output()
        .expect("run verbose gha-diag");
    assert_eq!(verbose.status.code(), Some(1));
    let verbose_stdout = String::from_utf8(verbose.stdout).expect("UTF-8 output");
    assert!(!verbose_stdout.contains("Validator:"));
    assert!(verbose_stdout.contains("Execution evidence:"));
    assert!(verbose_stdout.contains(&format!("Tool: gha-diag {}", env!("CARGO_PKG_VERSION"))));
    assert!(verbose_stdout.contains("Language server: @actions/languageserver"));
    assert!(verbose_stdout.contains("Experimental features: all"));
    for feature in experimental_features() {
        assert!(verbose_stdout.contains(&format!("[enabled ] {feature}")));
    }
    assert!(verbose_stdout.contains("Failure threshold: error"));
    assert!(verbose_stdout.contains("Empty input allowed: false"));
    assert!(verbose_stdout.contains("Runtime: Node.js"));
    assert!(
        verbose_stdout.contains(
            "Summary: files=3 workflows=2 actions=1 passed=2 failed=1 with_diagnostics=1"
        )
    );
    assert!(verbose_stdout.trim_end().ends_with("dependencies=0"));
}

#[test]
fn validates_with_the_bundled_language_server() {
    let repository = tempfile::tempdir().expect("repository");
    let workflows = repository.path().join(".github/workflows");
    fs::create_dir_all(&workflows).expect("workflow directory");
    fs::write(
        workflows.join("valid.yaml"),
        "on: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n",
    )
    .expect("valid workflow");
    fs::write(
        workflows.join("invalid.yaml"),
        "on: push\njobs:\n  build:\n    needs: missing\n    runs-on: ubuntu-latest\n",
    )
    .expect("invalid workflow");
    fs::write(
        workflows.join("caller.yaml"),
        "on: push\njobs:\n  reusable:\n    uses: ./.github/workflows/reusable.yaml\n",
    )
    .expect("caller workflow");
    fs::write(
        workflows.join("reusable.yaml"),
        "on:\n  workflow_call:\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n",
    )
    .expect("reusable workflow");

    let output = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args([
            "--node",
            &node(),
            "--format",
            "json",
            ".github/workflows/caller.yaml",
            ".github/workflows/invalid.yaml",
        ])
        .output()
        .expect("run gha-diag");
    assert_eq!(
        output.status.code(),
        Some(1),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let report: Value = serde_json::from_slice(&output.stdout).expect("JSON report");
    assert_eq!(report["schemaVersion"], "gha-diag-report-v1");
    assert_eq!(
        report["languageServer"]["experimentalFeatures"],
        serde_json::json!(experimental_features())
    );
    assert_eq!(
        report["languageServer"]["experimentalFeaturePolicy"]["mode"],
        "all"
    );
    assert_eq!(report["failureThreshold"], "error");
    assert_eq!(report["emptyInputAllowed"], false);
    assert_eq!(report["conclusion"], "failure");
    assert_eq!(report["exitCode"], 1);
    assert!(
        report["blockingDiagnostics"]
            .as_u64()
            .is_some_and(|count| count > 0)
    );
    assert_eq!(
        report["languageServer"]["version"],
        language_server_version()
    );
    assert_eq!(
        report["languageServer"]["bundleReproduction"]["byteForByte"],
        true
    );
    assert_eq!(
        report["languageServer"]["registryVerification"]["sourceDependencies"],
        true
    );
    assert_eq!(
        report["languageServer"]["registryVerification"]["reproductionDependencies"],
        true
    );
    assert_eq!(
        report["languageServer"]["provenancePredicateType"],
        "https://slsa.dev/provenance/v1"
    );
    assert_eq!(
        report["languageServer"]["bundleSha256"]
            .as_str()
            .map(str::len),
        Some(64)
    );
    assert_eq!(
        report["languageServer"]["licenseEvidence"]["nodeInventorySha256"]
            .as_str()
            .map(str::len),
        Some(64)
    );
    assert_eq!(report["languageServer"]["positionEncoding"], "utf-16");
    assert_eq!(report["hardening"]["nodePermissionModel"], true);
    assert!(
        report["diagnostics"]
            .as_array()
            .is_some_and(|values| !values.is_empty())
    );
    assert_eq!(report["files"].as_array().map(Vec::len), Some(2));
    assert!(
        report["files"]
            .as_array()
            .is_some_and(|files| files.iter().all(|file| file["kind"] == "workflow"))
    );
    let dependencies = report["readDependencies"]
        .as_array()
        .expect("read dependencies");
    assert!(dependencies.iter().any(|dependency| {
        dependency["path"] == ".github/workflows/reusable.yaml"
            && dependency["sha256"].as_str().map(str::len) == Some(64)
    }));
}

#[test]
fn lists_effective_experimental_features_without_starting_node() {
    let inventory = experimental_features();
    let output = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .env("GHA_DIAG_NODE", "/definitely/not/a/node")
        .args(["features", "--format", "json"])
        .output()
        .expect("list features");
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let report: Value = serde_json::from_slice(&output.stdout).expect("feature report");
    assert_eq!(report["schemaVersion"], "gha-diag-features-v1");
    assert_eq!(report["policy"], "all");
    let features = report["features"].as_array().expect("features");
    assert_eq!(features.len(), inventory.len());
    assert_eq!(
        features
            .iter()
            .map(|feature| feature["name"].as_str().expect("feature name"))
            .collect::<Vec<_>>(),
        inventory.iter().map(String::as_str).collect::<Vec<_>>()
    );
    assert!(
        features
            .iter()
            .all(|feature| { feature["enabled"] == true && feature["overridden"] == false })
    );

    if let Some(feature) = inventory.first() {
        let overridden = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
            .args([
                "features",
                "--format",
                "json",
                "--disable-experimental-feature",
                feature,
            ])
            .output()
            .expect("list overridden features");
        assert!(overridden.status.success());
        let report: Value =
            serde_json::from_slice(&overridden.stdout).expect("overridden feature report");
        assert!(report["features"].as_array().is_some_and(|features| {
            features.iter().any(|candidate| {
                candidate["name"] == feature.as_str()
                    && candidate["enabled"] == false
                    && candidate["overridden"] == true
            })
        }));
    }

    let text = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .args(["features", "--no-experimental-features"])
        .output()
        .expect("list disabled features");
    assert!(text.status.success());
    let stdout = String::from_utf8(text.stdout).expect("UTF-8");
    assert!(stdout.contains("Policy: none"));
    for feature in inventory {
        assert!(stdout.contains(&format!("[disabled] {feature}")));
    }
}

#[test]
fn rejects_unknown_experimental_feature_names() {
    let output = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .args([
            "features",
            "--disable-experimental-feature",
            "notARealFeature",
        ])
        .output()
        .expect("reject unknown feature");
    assert_eq!(output.status.code(), Some(2));
    let stderr = String::from_utf8(output.stderr).expect("UTF-8");
    assert!(stderr.contains("unknown experimental feature"));
}

#[test]
fn records_default_and_opt_out_feature_policies() {
    let repository = tempfile::tempdir().expect("repository");
    let workflow = repository.path().join("workflow.yaml");
    fs::write(
        &workflow,
        "on: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n",
    )
    .expect("workflow");

    let enabled = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--node", &node(), "--format", "json", "workflow.yaml"])
        .output()
        .expect("validate with all features");
    assert!(
        enabled.status.success(),
        "stdout: {}\nstderr: {}",
        String::from_utf8_lossy(&enabled.stdout),
        String::from_utf8_lossy(&enabled.stderr)
    );
    let enabled_report: Value = serde_json::from_slice(&enabled.stdout).expect("enabled report");
    assert!(
        enabled_report["diagnostics"]
            .as_array()
            .is_some_and(Vec::is_empty)
    );
    assert_eq!(
        enabled_report["languageServer"]["experimentalFeatures"],
        serde_json::json!(experimental_features())
    );

    let disabled = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args([
            "--node",
            &node(),
            "--format",
            "json",
            "--no-experimental-features",
            "workflow.yaml",
        ])
        .output()
        .expect("validate with background steps disabled");
    assert!(disabled.status.success());
    let disabled_report: Value = serde_json::from_slice(&disabled.stdout).expect("disabled report");
    assert_eq!(
        disabled_report["languageServer"]["experimentalFeaturePolicy"]["mode"],
        "none"
    );
    assert_eq!(
        disabled_report["languageServer"]["experimentalFeaturePolicy"]["disabled"],
        serde_json::json!(experimental_features())
    );
    assert_eq!(
        disabled_report["languageServer"]["experimentalFeatures"],
        serde_json::json!([])
    );
}

#[test]
fn warnings_are_reported_but_only_fail_at_the_requested_threshold() {
    if !experimental_features()
        .iter()
        .any(|feature| feature == "blockScalarChompingWarning")
    {
        return;
    }
    let repository = tempfile::tempdir().expect("repository");
    fs::write(
        repository.path().join("workflow.yaml"),
        "on: push\nenv:\n  VALUE: |\n    value\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n",
    )
    .expect("workflow with block scalar warning");

    let default = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--node", &node(), "--format", "json", "workflow.yaml"])
        .output()
        .expect("default threshold");
    assert!(default.status.success());
    let report: Value = serde_json::from_slice(&default.stdout).expect("warning report");
    assert_eq!(report["conclusion"], "success");
    assert_eq!(report["exitCode"], 0);
    assert_eq!(report["blockingDiagnostics"], 0);
    assert!(report["diagnostics"].as_array().is_some_and(|diagnostics| {
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic["severity"] == "warning")
    }));

    let strict = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--node", &node(), "--fail-on", "warning", "workflow.yaml"])
        .output()
        .expect("warning threshold");
    assert_eq!(strict.status.code(), Some(1));
}

#[test]
fn discovers_action_metadata_and_uses_the_action_validator() {
    let repository = tempfile::tempdir().expect("repository");
    let workflows = repository.path().join(".github/workflows");
    fs::create_dir_all(&workflows).expect("workflow directory");
    fs::write(
        repository.path().join("action.yml"),
        "name: Invalid pre-if action\ndescription: Proves action-specific validation\nruns:\n  using: node24\n  main: dist/index.js\n  pre: dist/pre.js\n  pre-if: ${{ runner.os == 'Windows' }}\n",
    )
    .expect("invalid action metadata");
    let nested = repository.path().join("nested");
    fs::create_dir_all(&nested).expect("nested action directory");
    fs::write(
        nested.join("action.yaml"),
        "name: Invalid post-if action\ndescription: Covers the alternate filename\nruns:\n  using: node24\n  main: dist/index.js\n  post: dist/post.js\n  post-if: ${{ always() }}\n",
    )
    .expect("invalid action.yaml metadata");
    fs::write(
        workflows.join("action.yml"),
        "on: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo workflow\n",
    )
    .expect("workflow named action.yml");

    let output = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--node", &node(), "--format", "json"])
        .output()
        .expect("run gha-diag");
    assert_eq!(
        output.status.code(),
        Some(1),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let report: Value = serde_json::from_slice(&output.stdout).expect("JSON report");
    let files = report["files"].as_array().expect("checked files");
    assert!(files.iter().any(|file| {
        file["path"] == "action.yml"
            && file["kind"] == "action"
            && file["sha256"].as_str().map(str::len) == Some(64)
    }));
    assert!(files.iter().any(|file| {
        file["path"] == ".github/workflows/action.yml" && file["kind"] == "workflow"
    }));
    assert!(files.iter().any(|file| {
        file["path"] == "nested/action.yaml"
            && file["kind"] == "action"
            && file["sha256"].as_str().map(str::len) == Some(64)
    }));
    let diagnostics = report["diagnostics"].as_array().expect("diagnostics");
    for path in ["action.yml", "nested/action.yaml"] {
        assert!(diagnostics.iter().any(|diagnostic| {
            diagnostic["file"] == path && diagnostic["code"] == "explicit-expression-not-allowed"
        }));
    }
    assert!(
        diagnostics
            .iter()
            .all(|diagnostic| diagnostic["file"] != ".github/workflows/action.yml")
    );
}

#[test]
fn rejects_an_empty_repository_unless_explicitly_allowed() {
    let repository = tempfile::tempdir().expect("repository");
    let rejected = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .arg("--format")
        .arg("json")
        .output()
        .expect("run gha-diag");
    assert_eq!(rejected.status.code(), Some(2));
    let report: Value = serde_json::from_slice(&rejected.stdout).expect("JSON report");
    assert_eq!(report["emptyInputAllowed"], false);
    assert_eq!(report["conclusion"], "failure");
    assert_eq!(report["exitCode"], 2);
    assert_eq!(report["blockingDiagnostics"], 0);
    assert_eq!(report["runtime"], Value::Null);
    assert_eq!(
        report["languageServer"]["bundleReproduction"]["byteForByte"],
        true
    );
    assert_eq!(
        report["languageServer"]["registryVerification"]["reproductionDependencies"],
        true
    );
    assert_eq!(report["readDependencies"].as_array().map(Vec::len), Some(0));

    let allowed = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .arg("--allow-empty")
        .output()
        .expect("run gha-diag");
    assert!(allowed.status.success());
    let stdout = String::from_utf8(allowed.stdout).expect("UTF-8 output");
    assert!(stdout.starts_with("Checked GitHub Actions files:\n  (none)\n"));
    assert!(!stdout.contains("Execution evidence:"));
    assert!(stdout.contains("experimental=all; fail-on=error; status=not-started"));
    assert!(stdout.contains("Result: PASS (exit_code=0, blocking_diagnostics=0)"));
    assert!(
        stdout
            .trim_end()
            .ends_with("Summary: files=0 workflows=0 actions=0 diagnostics=0")
    );

    let verbose = Command::new(env!("CARGO_BIN_EXE_gha-diag"))
        .current_dir(repository.path())
        .args(["--allow-empty", "--verbose"])
        .output()
        .expect("run verbose gha-diag");
    assert!(verbose.status.success());
    let stdout = String::from_utf8(verbose.stdout).expect("UTF-8 output");
    assert!(stdout.contains("Execution evidence:\n  Tool: gha-diag"));
    assert!(stdout.contains("Runtime: not started (no files discovered)"));
    assert!(stdout.contains("Empty input allowed: true"));
    assert!(stdout.trim_end().ends_with("dependencies=0"));
}
