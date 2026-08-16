{ ciCheck }:
{
  name = "ci-process-tests";
  fixture = "ciProcess";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  testFiles = [ "modules/features/ci/_tests/ci-process.bats" ];
  sourceFiles = [
    "modules/features/checks/_interface/bats/test-helper.bash"
    "modules/features/ci/_schemas/telemetry-v1.schema.json"
    "modules/features/ci/_scripts/ci_telemetry.py"
    "modules/features/ci/_scripts/optimize_hestia_matrix.py"
    "modules/features/ci/_scripts/validate_hestia_matrix.py"
    "modules/features/ci/_scripts/verify_binary_substituters.sh"
  ];
  initializeGit = false;
  platformPredicate = _platform: true;
}
