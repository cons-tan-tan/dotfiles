{
  config,
  lib,
  pkgs,
  username,
  homedir,
  ...
}:
{
  # Disable nix-darwin's Nix management (using Determinate Nix)
  # Note: Nix settings are managed via /etc/nix/nix.custom.conf instead
  # This file should be manually configured with trusted-users and substituters
  nix.enable = false;

  # Set system state version
  system.stateVersion = 5;

  # Set primary user
  system.primaryUser = username;

  # Define user
  users.users.${username} = {
    home = homedir;
  };

  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # Homebrew configuration
  # casks の置き場所の基準:
  #   - 単純な .app バンドルとして動く GUI アプリ
  #     → pkgs.brewCasks (nix/modules/darwin/packages.nix, brew-nix 管理)
  #   - インストーラ / 特権ヘルパー / 入力メソッド等のシステム統合を伴うもの
  #     → ここの homebrew.casks (実 Homebrew に任せる)
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";
    brews = [ ];
    casks = [
      "azookey"
      "fiji"
      "scroll-reverser"
      "tailscale-app"
    ];
    masApps = { };
  };
}
