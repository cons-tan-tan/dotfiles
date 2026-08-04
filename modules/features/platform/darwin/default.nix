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
      features.platform-darwin-packages
      features.platform-ghostty
      features.platform-sleepctl
      features.platform-nh
    ];
  };
}
