{ pkgs }:
let
  local = pkgs.dotfilesPackages;
  commonNames = [
    "agent-browser"
    "agent-command-guard"
    "agent-slack"
    "curl-fetch"
    "difit"
    "gh-api-get"
    "gha-lint"
    "ghq-fetch-all"
    "shellfirm"
    "zizmor"
  ];
  familyNames = [
    "aws"
    "claude-code"
    "codex"
    "hcom"
    "herdr"
    "hunk"
    "pi"
  ];
  platformNames =
    if pkgs.stdenv.hostPlatform.isLinux then
      [
        "ci-matrix-planner"
        "drawio-headless"
        "wsl-open"
        "wsl-set-ssh-auth-sock"
      ]
    else
      [
        "codex-app"
        "sleepctl"
      ];
  expectedNames = pkgs.lib.sort builtins.lessThan (commonNames ++ familyNames ++ platformNames);
  packageValues = (map (name: builtins.getAttr name local) commonNames) ++ [
    local.claude-code.package
    local.hcom.package
    local.herdr.package
    local.hunk.package
  ];
in
{
  testPrivateNamespaceExists = {
    expr = pkgs ? dotfilesPackages;
    expected = true;
  };

  testRepresentativePackagesExist = {
    expr = builtins.all (name: builtins.hasAttr name local) commonNames;
    expected = true;
  };

  testPackageInventoryIsExact = {
    expr = pkgs.lib.sort builtins.lessThan (builtins.attrNames local);
    expected = expectedNames;
  };

  testRepresentativePackagesAreDerivations = {
    expr = builtins.all pkgs.lib.isDerivation packageValues;
    expected = true;
  };

  testPlatformPackagesAreScoped = {
    expr =
      if pkgs.stdenv.hostPlatform.isLinux then
        local ? drawio-headless
        && local ? ci-matrix-planner
        && local ? wsl-open
        && local ? wsl-set-ssh-auth-sock
        && pkgs.lib.isDerivation local.wsl-open
        && !(local ? codex-app)
        && !(local ? sleepctl)
      else
        local ? codex-app
        && local ? sleepctl
        && pkgs.lib.isDerivation local.sleepctl
        && !(local ? drawio-headless)
        && !(local ? ci-matrix-planner)
        && !(local ? wsl-open)
        && !(local ? wsl-set-ssh-auth-sock);
    expected = true;
  };
}
