{ config, ... }:
{
  flake.modules.homeManager.terminal-default = {
    key = "modules/features/terminal/default.nix#homeManager.terminal-default";
    imports = [
      config.flake.modules.homeManager.terminal-fastfetch
      config.flake.modules.homeManager.terminal-yazi
    ];
  };
}
