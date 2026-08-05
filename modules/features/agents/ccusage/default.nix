{ ... }:
{
  features.agent-ccusage = {
    name = "feature/agents/ccusage";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.ccusage ];
      };
  };
}
