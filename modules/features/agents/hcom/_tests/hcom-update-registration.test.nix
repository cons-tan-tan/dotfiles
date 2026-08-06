{ pkgs }:
let
  package = pkgs.dotfilesPackages.hcom.package;
in
{
  testHcomOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "hcom";
    expected = true;
  };
}
