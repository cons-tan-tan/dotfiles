{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.optionals config.dotfiles.hcom.enable [
    pkgs.dotfilesPackages.hcom.package
  ];
}
