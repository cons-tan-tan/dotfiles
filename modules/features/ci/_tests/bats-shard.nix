{
  ciCheck,
  lib,
  repoRoot,
}:
let
  workflowFiles = (import ./workflows.nix { inherit lib; }).discover (
    repoRoot + "/.github/workflows"
  );
  ciScriptFiles = [
    "modules/features/ci/_scripts/assemble_ci_telemetry.py"
    "modules/features/ci/_scripts/capture_hestia_eval.py"
    "modules/features/ci/_scripts/ci_telemetry.py"
    "modules/features/ci/_scripts/collect_ci_telemetry.py"
    "modules/features/ci/_scripts/optimize_hestia_matrix.py"
    "modules/features/ci/_scripts/prefetch_hestia_closure_and_build.sh"
    "modules/features/ci/_scripts/run_hestia_build.py"
    "modules/features/ci/_scripts/validate_hestia_matrix.py"
    "modules/features/ci/_scripts/verify_binary_substituters.sh"
  ];
  pythonTestFiles = [
    "modules/features/ci/_tests/test_collect_ci_telemetry.py"
    "modules/features/ci/_tests/test_ci_telemetry.py"
    "modules/features/ci/_tests/test_optimize_hestia_matrix.py"
  ];
in
{
  name = "workflow-policy-tests";
  fixture = "workflowPolicy";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  testFiles = [ "modules/features/ci/_tests/workflow-policy.bats" ];
  sourceFiles =
    workflowFiles
    ++ ciScriptFiles
    ++ pythonTestFiles
    ++ [
      "modules/features/checks/_interface/bats/test-helper.bash"
      "modules/features/ci/_schemas/telemetry-run-index-v1.schema.json"
      "modules/features/ci/_schemas/telemetry-v1.schema.json"
    ];
  initializeGit = false;
  platformPredicate = _platform: true;
}
