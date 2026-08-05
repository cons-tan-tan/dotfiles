{ features, ... }:
{
  features.platform-linux = {
    name = "feature/platform/linux";
    includes = [
      features.platform-context
      features.platform-linux-drawio-headless
      features.platform-nh
    ];
  };
}
