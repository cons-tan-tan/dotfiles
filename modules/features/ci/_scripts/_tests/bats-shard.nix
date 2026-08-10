{ ciCheck, ... }:
{
  name = "gha-diag-update-tests";
  fixture = "ghaDiagUpdate";
  ciTargets = ciCheck.targets.linux "rust-and-bats";
  testFiles = [ "modules/features/ci/_scripts/_tests/update-gha-diag.bats" ];
  sourceFiles = [
    "modules/features/ci/_scripts/extract-gha-diag-experimental-features.mjs"
    "modules/features/ci/_scripts/generate-gha-diag-node-licenses.mjs"
    "modules/features/ci/_scripts/update-gha-diag.nix"
    "modules/features/ci/_scripts/update-gha-diag.sh"
  ];
  initializeGit = false;
  platformPredicate = _platform: true;
}
