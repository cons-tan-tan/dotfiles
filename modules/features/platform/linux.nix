{ features, ... }:
{
  features.platform-linux-packages = {
    name = "feature/platform/linux/packages";
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.drawio-headless ];
    };
  };

  features.platform-linux = {
    name = "feature/platform/linux";
    includes = [
      features.platform-context
      features.platform-linux-packages
      features.platform-nh
    ];
  };
}
