{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
}:
let
  ghaLintSupport = import ../../ci/_tests/gha-lint-support.nix { inherit lib pkgs; };
  zizmor = pkgs.dotfilesPackages.zizmor;
  # Duplicating diagnostics across the structural and security analyzers would
  # couple one tool's upgrade to both contracts. Repository bytes are the only
  # inputs, so a Darwin rerun would not add platform coverage either.
  workflowLint = ciCheck.annotate (ciCheck.targets.linux "repo-quality") (
    assert lib.assertMsg (lib.versionAtLeast zizmor.version "1.29.0")
      "workflow-lint-tests requires zizmor 1.29.0 or newer for self-repository references";
    pkgs.runCommand "workflow-lint-tests"
      {
        # Normal CLI runs follow the current upstream schema. The commit gate
        # pins fixtures so an upstream schema edit cannot change old commits.
        GHA_LINT_ACTION_SCHEMA = ghaLintSupport.schemas.action;
        GHA_LINT_WORKFLOW_SCHEMA = ghaLintSupport.schemas.workflow;
        nativeBuildInputs = [
          pkgs.dotfilesPackages.gha-lint
          zizmor
        ];
      }
      ''
        cd ${repoRoot}
        gha-lint
        zizmor --offline --persona=regular .
        touch "$out"
      ''
  );
  reuseLint = ciCheck.annotate (ciCheck.targets.linux "repo-quality") (
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
{
  owner = "repository quality checks";
  checks = lib.listToAttrs (
    [ (lib.nameValuePair "workflow-lint-tests" workflowLint) ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      (lib.nameValuePair "reuse-lint" reuseLint)
    ]
  );
}
