{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
}:
let
  support = import ./gha-lint-support.nix { inherit lib pkgs; };
  package = pkgs.dotfilesPackages.gha-lint;
  closure = pkgs.closureInfo { rootPaths = [ package ]; };
  smoke =
    pkgs.runCommand "gha-lint-smoke"
      {
        GHA_LINT_ACTION_SCHEMA = support.schemas.action;
        GHA_LINT_WORKFLOW_SCHEMA = support.schemas.workflow;
        nativeBuildInputs = [ package ];
      }
      ''
        test "$(gha-lint --version)" = "${package.version}"
        gha-lint --help > /dev/null
        gha-lint ${support.fixtures.workflow}
        gha-lint ${support.fixtures.actionDirectory}/action.yml

        ${pkgs.gnugrep}/bin/grep -qi shellcheck ${closure}/store-paths
        if ${pkgs.gnugrep}/bin/grep -Fxq ${support.schemas.workflow} ${closure}/store-paths \
          || ${pkgs.gnugrep}/bin/grep -Fxq ${support.schemas.action} ${closure}/store-paths; then
          echo "gha-lint runtime closure contains a fixed test schema" >&2
          exit 1
        fi
        if ${pkgs.gnugrep}/bin/grep -Eqi '/(node(js)?|bun|check-json(schema)?)-' ${closure}/store-paths; then
          echo "gha-lint runtime closure contains a forbidden runtime" >&2
          exit 1
        fi

        touch "$out"
      '';
  pythonTests = ciCheck.annotate (ciCheck.targets.linux "rust-and-bats") (
    pkgs.runCommand "ci-python-tests"
      {
        nativeBuildInputs = [
          pkgs.check-jsonschema
          pkgs.python3
        ];
      }
      ''
        cd ${repoRoot}
        export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
        python3 -m py_compile modules/features/ci/_scripts/*.py
        python3 -m unittest \
          modules/features/ci/_tests/test_collect_ci_telemetry.py \
          modules/features/ci/_tests/test_ci_telemetry.py \
          modules/features/ci/_tests/test_optimize_hestia_matrix.py
        touch "$out"
      ''
  );
  sourceLint = ciCheck.annotate (ciCheck.targets.linux "rust-and-bats") (
    pkgs.runCommand "ci-source-lint"
      {
        nativeBuildInputs = [
          pkgs.check-jsonschema
          pkgs.shellcheck
        ];
      }
      ''
        shellcheck \
          ${repoRoot}/modules/features/ci/_scripts/prefetch_hestia_closure_and_build.sh \
          ${repoRoot}/modules/features/ci/_scripts/update_pins_smoke.sh \
          ${repoRoot}/modules/features/ci/_scripts/verify_binary_substituters.sh \
          ${repoRoot}/modules/features/ci/_scripts/verify_hestia_result.sh \
          ${repoRoot}/modules/features/ci/_scripts/verify_required_results.sh
        check-jsonschema --check-metaschema \
          ${repoRoot}/modules/features/ci/_schemas/telemetry-v1.schema.json
        check-jsonschema --check-metaschema \
          ${repoRoot}/modules/features/ci/_schemas/telemetry-run-index-v1.schema.json
        touch "$out"
      ''
  );
in
{
  owner = "CI tooling checks";
  artifacts = [
    {
      name = "gha-lint";
      path = smoke;
    }
  ];
  checks = {
    ci-python-tests = pythonTests;
    ci-source-lint = sourceLint;
  };
}
