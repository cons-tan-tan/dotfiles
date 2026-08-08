{ features, ... }:
{
  features.platform-linux = {
    name = "feature/platform/linux";
    includes = [
      features.platform-context
      features.drawio-linux-headless
      features.platform-nh
    ];
  };
}
