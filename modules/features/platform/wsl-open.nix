{ ... }:
{
  features.platform-wsl-open = {
    name = "feature/platform/wsl-open";
    homeManager =
      { pkgs, ... }:
      let
        wsl-open = pkgs.callPackage ./_lib/wsl-open-package.nix { };
      in
      {
        home.packages = [ wsl-open ];
        home.sessionVariables.BROWSER = "wsl-open";
      };
  };
}
