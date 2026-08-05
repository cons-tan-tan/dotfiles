{ features, ... }:
{
  features.platform-darwin = {
    name = "feature/platform/darwin";
    includes = [
      features.platform-context
      features.platform-darwin-system
      features.platform-darwin-fonts
      features.platform-darwin-touch-id
      features.platform-homebrew
      features.input-methods-azookey
      features.media-aqua-voice
      features.media-fiji
      features.network-tailscale
      features.platform-darwin-scroll-reverser
      features.productivity-raycast
      features.platform-ghostty
      features.platform-sleepctl
      features.platform-nh
    ];
  };
}
