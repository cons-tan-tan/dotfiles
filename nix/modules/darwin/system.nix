{
  config,
  lib,
  pkgs,
  username,
  homedir,
  ...
}:
{
  imports = [
    ./sleepctl-daemon.nix
  ];

  # Disable nix-darwin's Nix management (using Determinate Nix)
  # Note: Nix settings are managed via /etc/nix/nix.custom.conf instead
  # This file should be manually configured with trusted-users and substituters
  nix.enable = false;

  system.stateVersion = 5;

  system.primaryUser = username;

  users.users.${username} = {
    home = homedir;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # casks の置き場所の基準:
  #   - 単純な .app バンドルとして動く GUI アプリ
  #     → pkgs.brewCasks (nix/modules/darwin/packages.nix, brew-nix 管理)
  #   - インストーラ / 特権ヘルパー / 入力メソッド等のシステム統合を伴うもの
  #     → ここの homebrew.casks (実 Homebrew に任せる)
  homebrew = {
    enable = true;
    onActivation = {
      # nix-darwin d5bd9cd maps cleanup = "uninstall" to --force-cleanup,
      # but Homebrew Bundle now accepts --cleanup for install-time cleanup.
      cleanup = "none";
      extraFlags = [ "--cleanup" ];
    };
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
