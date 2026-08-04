{ features, ... }:
{
  features.agent-codex = {
    name = "feature/agents/codex";
    includes = [
      features.agents-base
      features.agent-herdr
    ];
    homeManager = import ./_lib/home/codex.nix;
  };
}
