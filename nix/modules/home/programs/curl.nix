{ pkgs, ... }:
{
  home.packages = [
    pkgs.curl
    pkgs.dotfilesPackages.curl-fetch
  ];
}
