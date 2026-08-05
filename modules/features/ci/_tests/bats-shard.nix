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
    "modules/features/ci/_scripts/prefetch_hestia_closure_and_build.sh"
    "modules/features/ci/_scripts/validate_hestia_matrix.py"
    "modules/features/ci/_scripts/verify_binary_substituters.sh"
  ];
in
{
  name = "workflow-policy-tests";
  fixture = "workflowPolicy";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  testFiles = [ "modules/features/ci/_tests/workflow-policy.bats" ];
  sourceFiles =
    workflowFiles ++ ciScriptFiles ++ [ "modules/features/checks/_lib/bats/test-helper.bash" ];
  initializeGit = false;
  platformPredicate = _platform: true;
}
