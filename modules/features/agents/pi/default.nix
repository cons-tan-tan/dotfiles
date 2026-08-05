{ features, ... }:
{
  features.agent-pi = {
    name = "feature/agents/pi";
    includes = [
      features.agents-base
      features.agent-herdr
    ];
  };
}
