{ features, ... }:
{
  features.agent-opencode = {
    name = "feature/agents/opencode";
    includes = [
      features.agent-guidance
      features.agent-herdr
    ];
  };
}
