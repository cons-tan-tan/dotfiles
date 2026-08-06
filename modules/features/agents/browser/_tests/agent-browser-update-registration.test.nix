{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-browser;
in
{
  testAgentBrowserOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "agent-browser";
    expected = true;
  };
}
