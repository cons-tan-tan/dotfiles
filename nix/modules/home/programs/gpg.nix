{ pkgs, lib, ... }:
let
  pinentryPackage = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-curses;
in
{
  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pinentryPackage;
    defaultCacheTtl = 43200;
    maxCacheTtl = 43200;
  };

  home.packages = [ pinentryPackage ];
}
