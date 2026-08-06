{ pkgs }:
{
  testWatchexecOwnsItsUpdateScript = {
    expr =
      builtins.isString pkgs.watchexec.updateScript && pkgs.watchexec.updateScriptName == "watchexec";
    expected = true;
  };
}
