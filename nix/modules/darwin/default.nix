{ ... }:
# NOTE: ここ (nix-darwin の system スコープ) では config.my.* は参照できない。
# my.* オプション (nix/modules/options.nix) は mk-home-modules.nix 経由で
# HM サブモジュールにのみ import される。system スコープで hostKind 分岐が
# 必要になったら、mk-darwin.nix の specialArgs で渡すこと。
{
  imports = [
    ./packages.nix
    ./programs
  ];

  # macOS-specific home-manager configuration
  # Add additional macOS-specific settings here as needed
}
