{ config, ... }:
{
  flake.modules.homeManager.platform-wsl = {
    key = "modules/features/platform/wsl/default.nix#homeManager.platform-wsl";
    imports = [
      config.flake.modules.homeManager.platform-context
      config.flake.modules.homeManager.drawio-linux-headless
      config.flake.modules.homeManager.nix-lifecycle-wsl
      config.flake.modules.homeManager.platform-wsl-open
      config.flake.modules.homeManager.windows-default
    ];
  };

  flake.modules.nixos.platform-wsl = {
    key = "modules/features/platform/wsl/default.nix#nixos.platform-wsl";
    imports = [
      config.flake.modules.nixos.platform-wsl-base
      config.flake.modules.nixos.platform-wsl-docker
      config.flake.modules.nixos.platform-wsl-memory
      config.flake.modules.nixos.nix-settings-wsl
      config.flake.modules.nixos.nix-lifecycle-wsl
    ];
  };
}
