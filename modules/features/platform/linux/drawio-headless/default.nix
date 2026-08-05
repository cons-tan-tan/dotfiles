_: {
  features.platform-linux-drawio-headless = {
    name = "feature/platform/linux/drawio-headless";
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.drawio-headless ];
    };
  };
}
