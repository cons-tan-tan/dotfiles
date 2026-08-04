{ features, ... }:
{
  features.platform-wsl = {
    name = "feature/platform/wsl";
    includes = [
      features.platform-context
      features.platform-linux-packages
      features.platform-wsl-base
      features.platform-wsl-docker
      features.platform-wsl-memory
      features.platform-nix-settings
      features.platform-nh
      features.platform-wsl-open
      features.windows-default
    ];
  };
}
