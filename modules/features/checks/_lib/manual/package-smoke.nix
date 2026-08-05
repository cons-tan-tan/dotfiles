{
  ciCheck,
  lib,
  pkgs,
}:
let
  sourceControlPackageSources = import ../../../source-control/_interface/package-sources.nix;
  ghaLintSupport = import ../../../ci/_tests/gha-lint-support.nix { inherit lib pkgs; };
  ghaLintClosure = pkgs.closureInfo {
    rootPaths = [ pkgs.dotfilesPackages.gha-lint ];
  };
  ghqFetchAllSmokePackage =
    let
      fakeGhq = pkgs.writeShellApplication {
        name = "ghq";
        text = ''printf '%s\n' /tmp/repo'';
      };
      fakeGit = pkgs.writeShellApplication {
        name = "git";
        text = "exit 0";
      };
    in
    pkgs.callPackage sourceControlPackageSources.ghqFetchAll {
      ghq = fakeGhq;
      git = fakeGit;
    };
in
{
  owner = "package smoke checks";
  checks = {
    pi-package-layout = ciCheck.annotate (ciCheck.targets.both "package-smoke") (
      pkgs.runCommand "pi-package-layout" { } ''
        test -f ${pkgs.pi}/libexec/pi/package.json
        test -x ${pkgs.pi}/libexec/pi/pi
        touch "$out"
      ''
    );
    package-smoke-tests = ciCheck.annotate (ciCheck.targets.both "package-smoke") (
      pkgs.runCommand "package-smoke-tests"
        {
          GHA_LINT_ACTION_SCHEMA = ghaLintSupport.schemas.action;
          GHA_LINT_WORKFLOW_SCHEMA = ghaLintSupport.schemas.workflow;
          nativeBuildInputs = [
            pkgs.dotfilesPackages.agent-browser
            pkgs.dotfilesPackages.agent-slack
            pkgs.dotfilesPackages.difit
            pkgs.dotfilesPackages.gha-lint
          ];
        }
        ''
          agent_browser_version="$(agent-browser --version 2>&1)"
          test -n "$agent_browser_version"

          agent_slack_version="$(agent-slack --version 2>&1)"
          test -n "$agent_slack_version"

          test "$(difit --version)" = "${pkgs.dotfilesPackages.difit.version}"
          difit --help >/dev/null

          test "$(gha-lint --version)" = "${pkgs.dotfilesPackages.gha-lint.version}"
          gha-lint --help >/dev/null
          gha-lint ${ghaLintSupport.fixtures.workflow}
          gha-lint ${ghaLintSupport.fixtures.actionDirectory}/action.yml

          ${pkgs.gnugrep}/bin/grep -qi shellcheck ${ghaLintClosure}/store-paths
          if ${pkgs.gnugrep}/bin/grep -Fxq ${ghaLintSupport.schemas.workflow} ${ghaLintClosure}/store-paths \
            || ${pkgs.gnugrep}/bin/grep -Fxq ${ghaLintSupport.schemas.action} ${ghaLintClosure}/store-paths; then
            echo "gha-lint runtime closure contains a fixed test schema" >&2
            exit 1
          fi
          if ${pkgs.gnugrep}/bin/grep -Eqi '/(node(js)?|bun|check-json(schema)?)-' ${ghaLintClosure}/store-paths; then
            echo "gha-lint runtime closure contains a forbidden runtime" >&2
            exit 1
          fi

          # The service starts the package directly, so every subprocess must
          # remain available without inheriting the activating user's PATH.
          PATH=/nonexistent ${ghqFetchAllSmokePackage}/bin/ghq-fetch-all

          touch "$out"
        ''
    );
  };
}
