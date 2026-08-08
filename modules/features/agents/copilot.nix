{ den, ... }:
{
  features.agent-copilot = {
    name = "feature/agents/copilot";
    includes = [
      (den.batteries.unfree [ "github-copilot-cli" ])
    ];
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.github-copilot-cli ];
      };
  };
}
