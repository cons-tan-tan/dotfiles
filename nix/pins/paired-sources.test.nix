{ pkgs }:
let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  lockedRef = name: lock.nodes.${name}.original.ref or null;
in
{
  testAgentBrowserSkillMatchesPackageVersion = {
    expr = lockedRef "agent-browser-skill";
    expected = "v${pkgs.agent-browser.version}";
  };

  testAgentSlackSkillMatchesPackageVersion = {
    expr = lockedRef "agent-slack-skill";
    expected = "v${pkgs.agent-slack.version}";
  };

  testDifitSkillMatchesPackageVersion = {
    expr = lockedRef "difit-src";
    expected = "v${pkgs.difit.version}";
  };

  testHcomSkillMatchesPackageVersion = {
    expr = lockedRef "hcom-src";
    expected = "v${pkgs.hcom.version}";
  };
}
