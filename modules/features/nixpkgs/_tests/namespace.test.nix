{ pkgs }:
let
  local = pkgs.dotfilesPackages;
  commonNames = [
    "agent-browser"
    "agent-command-guard"
    "agent-slack"
    "bee"
    "curl-fetch"
    "difit"
    "gh-api-get"
    "gha-diag"
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
        "oo7-dpapi-bridge"
        "wsl-dpapi"
        "wsl-open"
        "wsl-set-ssh-auth-sock"
      ]
    else
      [
        "codex-app"
        "sleepctl"
      ];
  expectedNames = pkgs.lib.sort builtins.lessThan (commonNames ++ familyNames ++ platformNames);
in
{
  testPackageInventoryIsExact = {
    expr = pkgs.lib.sort builtins.lessThan (builtins.attrNames local);
    expected = expectedNames;
  };

  testPlatformPackagesAreDerivations = {
    expr = builtins.all pkgs.lib.isDerivation (map (name: local.${name}) platformNames);
    expected = true;
  };
}
