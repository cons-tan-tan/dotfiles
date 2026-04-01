{ pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;

in
{
  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry =
      if isDarwin then
        { package = pkgs.pinentry_mac; }
      else
        { package = null; };
    extraConfig = lib.optionalString (!isDarwin) ''
      pinentry-program /mnt/c/Users/zhouc/scoop/apps/gpg4win/current/Gpg4win/bin/pinentry.exe
    '';
    defaultCacheTtl = 43200;
    maxCacheTtl = 43200;
    sshKeys = [
      # keygrip
      "60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD"
    ];
  };
}
