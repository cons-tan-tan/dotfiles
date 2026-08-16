{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
}:
let
  support = import ./gha-diag-support.nix { };
  package = pkgs.dotfilesPackages.gha-diag;
  closure = pkgs.closureInfo { rootPaths = [ package ]; };
  plannerPython = pkgs.dotfilesPackages.ci-matrix-planner.python;
  smoke = pkgs.runCommand "gha-diag-smoke" { nativeBuildInputs = [ package ]; } ''
    gha-diag --version | grep -Fx "gha-diag ${package.version}"
    gha-diag --help > /dev/null
    gha-diag features --format json > features.json
    ${lib.getExe pkgs.jq} -e \
      --argjson expected '${builtins.toJSON (builtins.fromJSON (builtins.readFile ../_packages/gha-diag/language-server.json)).experimentalFeatures}' \
      '[.features[] | select(.enabled) | .name] == $expected and
       ([.features[] | select(.overridden)] | length == 0)' \
      features.json >/dev/null
    (
      cd ${support.fixtures.directory}
      gha-diag valid.yaml
      gha-diag action.yml
    )
    test -s ${package}/share/licenses/gha-diag/gha-diag-LICENSE-CC0-1.0
    test -s ${package}/share/licenses/gha-diag/actions-languageserver-LICENSE
    test -s ${package}/share/licenses/gha-diag/actions-languageserver-LICENSE-THIRD-PARTY
    test -s ${package}/share/licenses/gha-diag/actions-languageserver-third-party-licenses.json
    test -s ${package}/share/licenses/gha-diag/LICENSE-RUST-THIRD-PARTY

    if ! ${pkgs.gnugrep}/bin/grep -Eqi -- '-node(js)?-' ${closure}/store-paths; then
      echo "gha-diag runtime closure does not contain Node.js" >&2
      exit 1
    fi
    if ${pkgs.gnugrep}/bin/grep -Eqi -- '-(bun|pnpm|shellcheck|check-json(schema)?)-' ${closure}/store-paths; then
      echo "gha-diag runtime closure contains an unexpected build-time tool" >&2
      exit 1
    fi

    touch "$out"
  '';
  pythonTests = ciCheck.buildEntry (ciCheck.targets.linux "rust-and-bats") (
    pkgs.runCommand "ci-python-tests"
      {
        nativeBuildInputs = [
          pkgs.check-jsonschema
          plannerPython
        ];
      }
      ''
        cd ${repoRoot}
        export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
        ${plannerPython}/bin/python3 -m py_compile modules/features/ci/_scripts/*.py
        ${plannerPython}/bin/python3 -m unittest \
          modules/features/ci/_tests/test_capture_workflow_timing.py \
          modules/features/ci/_tests/test_collect_ci_telemetry.py \
          modules/features/ci/_tests/test_ci_telemetry.py \
          modules/features/ci/_tests/test_download_ci_telemetry_history.py \
          modules/features/ci/_tests/test_optimize_hestia_matrix.py \
          modules/features/ci/_tests/test_plan_ci_matrix.py
        touch "$out"
      ''
  );
  sourceLint = ciCheck.buildEntry (ciCheck.targets.linux "rust-and-bats") (
    pkgs.runCommand "ci-source-lint"
      {
        nativeBuildInputs = [
          pkgs.check-jsonschema
          pkgs.shellcheck
        ];
      }
      ''
        shellcheck \
          ${repoRoot}/modules/features/ci/_scripts/update-gha-diag.sh \
          ${repoRoot}/modules/features/ci/_scripts/verify_binary_substituters.sh
        check-jsonschema --check-metaschema \
          ${repoRoot}/modules/features/ci/_schemas/telemetry-v1.schema.json
        check-jsonschema --check-metaschema \
          ${repoRoot}/modules/features/ci/_schemas/telemetry-run-index-v1.schema.json
        check-jsonschema --check-metaschema \
          ${repoRoot}/modules/features/ci/_schemas/ci-optimization-v1.schema.json
        check-jsonschema --check-metaschema \
          ${repoRoot}/modules/features/ci/_schemas/ci-optimization-v2.schema.json
        touch "$out"
      ''
  );
in
{
  owner = "CI tooling checks";
  artifacts = [
    {
      name = "gha-diag";
      path = smoke;
    }
  ];
  buildEntries = {
    ci-source-lint = sourceLint;
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    ci-python-tests = pythonTests;
  };
}
