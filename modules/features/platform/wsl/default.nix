{ features, ... }:
{
  features.platform-wsl = {
    name = "feature/platform/wsl";
    includes = [
      features.platform-context
      features.drawio-linux-headless
      features.platform-wsl-base
      features.platform-wsl-docker
      features.platform-wsl-memory
      features.nix-settings-wsl
      features.nix-lifecycle-wsl
      features.platform-wsl-open
      features.windows-default
    ];
  };
}
