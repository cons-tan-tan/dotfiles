{ pkgs }:
let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  lockedRef =
    name:
    let
      nodeName = lock.nodes.root.inputs.${name};
    in
    if builtins.isString nodeName then
      lock.nodes.${nodeName}.original.ref or null
    else
      throw "${name} must be a direct root flake input";
in
{
  testAgentBrowserSkillMatchesPackageVersion = {
    expr = lockedRef "agent-browser-skill";
    expected = "v${pkgs.dotfilesPackages.agent-browser.version}";
  };

  testAgentSlackSkillMatchesPackageVersion = {
    expr = lockedRef "agent-slack-skill";
    expected = "v${pkgs.dotfilesPackages.agent-slack.version}";
  };

  testDifitSkillMatchesPackageVersion = {
    expr = lockedRef "difit-src";
    expected = "v${pkgs.dotfilesPackages.difit.version}";
  };

  testHcomSkillMatchesPackageVersion = {
    expr = lockedRef "hcom-src";
    expected = "v${pkgs.dotfilesPackages.hcom.package.version}";
  };
}
