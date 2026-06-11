# flake registry に `dotfiles` を登録し、任意の cwd から
# `nix run dotfiles#<app>` を可能にする。
#
# ブートストラップ前提: 参照先は my.dotfilesDir の「パス」なので、この
# リポジトリが所定の場所に clone されるまでは `nix run dotfiles#...` は
# 壊れている。初回セットアップは clone したリポジトリ内で `nix run .#switch`
# を実行すること (README 参照)。
{ config, ... }:
{
  nix.registry.dotfiles = {
    from = {
      type = "indirect";
      id = "dotfiles";
    };

    to = {
      type = "path";
      path = config.my.dotfilesDir;
    };
  };
}
