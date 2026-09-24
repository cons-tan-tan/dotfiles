{ config, ... }:
{
  flake.modules.homeManager.agent-pi = {
    key = "modules/features/agents/pi/default.nix#homeManager.agent-pi";
    imports = [
      config.flake.modules.homeManager.agents-base
      config.flake.modules.homeManager.agent-herdr
    ];
  };
}
