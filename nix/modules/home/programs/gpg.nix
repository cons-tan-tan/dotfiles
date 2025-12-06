{ pkgs, ... }:
{
  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;
    pinentry.package = pkgs.pinentry-curses;
    defaultCacheTtl = 43200;
    maxCacheTtl = 43200;
  };
}
