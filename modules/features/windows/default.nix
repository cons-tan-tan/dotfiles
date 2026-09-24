{ config, ... }:
{
  flake.modules.homeManager.windows-default = {
    key = "modules/features/windows/default.nix#homeManager.windows-default";
    imports = [
      config.flake.modules.homeManager.windows-base
      config.flake.modules.homeManager.windows-powershell
      config.flake.modules.homeManager.cli-tools-winget
    ];
  };
}
