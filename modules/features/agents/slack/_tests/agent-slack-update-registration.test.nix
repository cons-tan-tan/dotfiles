{ pkgs }:
let
  package = pkgs.dotfilesPackages.agent-slack;
in
{
  testAgentSlackOwnsItsUpdateScript = {
    expr = builtins.isString package.updateScript && package.updateScriptName == "agent-slack";
    expected = true;
  };
}
