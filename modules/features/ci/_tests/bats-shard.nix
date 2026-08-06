{
  ciCheck,
  lib,
  repoRoot,
}:
let
  workflowFiles = (import ./workflows.nix { inherit lib; }).discover (
    repoRoot + "/.github/workflows"
  );
in
{
  name = "workflow-policy-tests";
  fixture = "workflowPolicy";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  testFiles = [ "modules/features/ci/_tests/workflow-policy.bats" ];
  sourceFiles = workflowFiles ++ [ ".github/actions/setup-hestia/action.yaml" ];
  initializeGit = false;
  platformPredicate = _platform: true;
}
