{ pkgs }:
let
  package = pkgs.dotfilesPackages.herdr.package;
in
{
  testHerdrOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "herdr";
    expected = true;
  };
}
