{ config, ... }:
{
  flake.modules.homeManager.trash-systemd = {
    key = "modules/features/trash/default.nix#homeManager.trash-systemd";
    imports = [
      config.flake.modules.homeManager.trash
    ];
  };

  flake.modules.homeManager.trash-darwin = {
    key = "modules/features/trash/default.nix#homeManager.trash-darwin";
    imports = [
      config.flake.modules.homeManager.trash
    ];
  };
}
