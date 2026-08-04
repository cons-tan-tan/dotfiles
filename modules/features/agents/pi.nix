{ features, ... }:
{
  features.agent-pi = {
    name = "feature/agents/pi";
    includes = [
      features.agents-base
      features.agent-herdr
    ];
    homeManager = import ./_lib/home/pi.nix;
  };
}
