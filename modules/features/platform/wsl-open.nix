{ ... }:
{
  features.platform-wsl-open = {
    name = "feature/platform/wsl-open";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.dotfilesPackages.wsl-open ];
        home.sessionVariables.BROWSER = "wsl-open";
      };
  };
}
