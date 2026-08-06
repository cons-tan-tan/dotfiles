{ pkgs }:
let
  package = pkgs.dotfilesPackages.difit;
in
{
  testDifitOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "difit";
    expected = true;
  };
}
