{ pkgs }:
let
  package = pkgs.dotfilesPackages.gha-diag;
in
{
  testGhaDiagOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "gha-diag";
    expected = true;
  };
}
