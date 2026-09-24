{ config, ... }:
{
  flake.modules.darwin.platform-darwin = {
    key = "modules/features/platform/darwin/default.nix#darwin.platform-darwin";
    imports = [
      config.flake.modules.darwin.platform-darwin-system
      config.flake.modules.darwin.platform-darwin-fonts
      config.flake.modules.darwin.platform-darwin-touch-id
      config.flake.modules.darwin.platform-homebrew
      config.flake.modules.darwin.input-methods-azookey
      config.flake.modules.darwin.media-fiji
      config.flake.modules.darwin.network-tailscale
      config.flake.modules.darwin.platform-darwin-scroll-reverser
      config.flake.modules.darwin.platform-sleepctl
    ];
  };

  flake.modules.homeManager.platform-darwin = {
    key = "modules/features/platform/darwin/default.nix#homeManager.platform-darwin";
    imports = [
      config.flake.modules.homeManager.platform-context
      config.flake.modules.homeManager.media-aqua-voice
      config.flake.modules.homeManager.productivity-raycast
      config.flake.modules.homeManager.platform-ghostty
      config.flake.modules.homeManager.platform-sleepctl
      config.flake.modules.homeManager.nix-lifecycle
    ];
  };
}
