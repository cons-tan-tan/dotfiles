{ pkgs, ... }:
{
  home.packages = [
    pkgs.dotfilesPackages.drawio-headless
  ];
}
