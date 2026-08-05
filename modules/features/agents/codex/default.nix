{
  den,
  features,
  ...
}:
{
  features.agent-codex = {
    name = "feature/agents/codex";
    includes = [
      features.agents-base
      features.agent-hcom-contract
      features.agent-herdr
      (den.batteries.unfree [ "codex-app" ])
    ];
  };
}
