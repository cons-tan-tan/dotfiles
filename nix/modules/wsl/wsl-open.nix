{ pkgs, ... }:
let
  wsl-open = pkgs.callPackage ./wsl-open-package.nix { };
in
{
  home.packages = [ wsl-open ];

  home.sessionVariables = {
    BROWSER = "wsl-open";
  };
}
