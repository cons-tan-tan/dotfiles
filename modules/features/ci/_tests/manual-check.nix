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
          pkgs.python3
        ];
      }
      ''
        cd ${repoRoot}
        export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
        ${pkgs.python3}/bin/python3 -m py_compile modules/features/ci/_scripts/*.py
        ${pkgs.python3}/bin/python3 -m unittest \
          modules/features/ci/_tests/test_optimize_hestia_matrix.py \
          modules/features/ci/_tests/test_hestia_runtime.py
        touch "$out"
      ''
  );
  sourceLint = ciCheck.buildEntry (ciCheck.targets.linux "rust-and-bats") (
    pkgs.runCommand "ci-source-lint"
      {
        nativeBuildInputs = [
          pkgs.shellcheck
        ];
      }
      ''
        shellcheck \
          ${repoRoot}/modules/features/ci/_scripts/update-gha-diag.sh \
          ${repoRoot}/modules/features/ci/_scripts/verify_binary_substituters.sh
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
