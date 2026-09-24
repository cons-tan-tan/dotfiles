{ config, ... }:
{
  flake.modules.homeManager.platform-linux = {
    key = "modules/features/platform/linux.nix#homeManager.platform-linux";
    imports = [
      config.flake.modules.homeManager.platform-context
      config.flake.modules.homeManager.drawio-linux-headless
      config.flake.modules.homeManager.nix-lifecycle
    ];
  };
}
