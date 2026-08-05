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
      features.agent-herdr
      (den.batteries.unfree [ "codex-app" ])
    ];
    homeManager = import ./_lib/home.nix;
  };
}
