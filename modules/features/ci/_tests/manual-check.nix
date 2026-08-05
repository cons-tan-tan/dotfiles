{ lib, pkgs }:
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
in
{
  owner = "gha-lint package smoke";
  artifacts = [
    {
      name = "gha-lint";
      path = smoke;
    }
  ];
  checks = { };
}
