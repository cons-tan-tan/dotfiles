{ pkgs }:
let
  updater = pkgs.dotfilesPackages.codex.appUpdater;
in
{
  testCodexFamilyOwnsAppUpdateScript = {
    expr = builtins.isString updater.updateScript && updater.updateScriptName == "codex-app";
    expected = true;
  };
}
