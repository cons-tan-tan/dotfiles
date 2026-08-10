{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
}:
let
  zizmor = pkgs.dotfilesPackages.zizmor;
  # Duplicating diagnostics across the structural and security analyzers would
  # couple one tool's upgrade to both contracts. Repository bytes are the only
  # inputs, so a Darwin rerun would not add platform coverage either.
  workflowLint = ciCheck.buildEntry (ciCheck.targets.linux "repo-quality") (
    assert lib.assertMsg (lib.versionAtLeast zizmor.version "1.29.0")
      "workflow-lint-tests requires zizmor 1.29.0 or newer for self-repository references";
    pkgs.runCommand "workflow-lint-tests"
      {
        nativeBuildInputs = [
          pkgs.dotfilesPackages.gha-diag
          zizmor
        ];
      }
      ''
        cd ${repoRoot}
        gha-diag
        zizmor --offline --persona=regular .
        touch "$out"
      ''
  );
  reuseLint = ciCheck.buildEntry (ciCheck.targets.linux "repo-quality") (
    # Provenance depends only on repository bytes, not the runner platform.
    pkgs.runCommand "reuse-lint"
      {
        nativeBuildInputs = [ pkgs.reuse ];
      }
      ''
        cd ${repoRoot}
        reuse lint
        touch "$out"
      ''
  );
in
ciCheck.mkBuildProducer {
  owner = "repository quality checks";
  entries = lib.listToAttrs (
    [ (lib.nameValuePair "workflow-lint-tests" workflowLint) ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      (lib.nameValuePair "reuse-lint" reuseLint)
    ]
  );
}
