{ pkgs, lib, ... }:
{
  imports = [
    ./packages.nix
    ./programs
  ];

  home = {
    stateVersion = "24.11";

    # Enable Home Manager
    enableNixpkgsReleaseCheck = false;
  };

  programs.home-manager.enable = true;
}
