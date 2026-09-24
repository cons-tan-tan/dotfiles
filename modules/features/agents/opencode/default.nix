{ config, ... }:
{
  flake.modules.homeManager.agent-opencode = {
    key = "modules/features/agents/opencode/default.nix#homeManager.agent-opencode";
    imports = [
      config.flake.modules.homeManager.agent-guidance
      config.flake.modules.homeManager.agent-herdr
    ];
  };
}
