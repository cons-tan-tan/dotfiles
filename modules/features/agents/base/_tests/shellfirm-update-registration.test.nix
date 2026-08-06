{ pkgs }:
let
  package = pkgs.dotfilesPackages.shellfirm;
in
{
  testShellfirmOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "shellfirm";
    expected = true;
  };
}
