{ config, ... }:
{
  flake.modules.homeManager.editors-default = {
    key = "modules/features/editors/default.nix#homeManager.editors-default";
    imports = [
      config.flake.modules.homeManager.editors-neovim
      config.flake.modules.homeManager.editors-zed
    ];
  };
}
