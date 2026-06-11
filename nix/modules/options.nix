# my.* 名前空間: ホスト構成パラメータを specialArgs ではなく module options で
# 配る。値は nix/lib/mk-home-modules.nix が設定し、各モジュールは config.my.*
# を読む。
{ config, lib, ... }:
let
  cfg = config.my;
in
{
  options.my = {
    hostKind = lib.mkOption {
      type = lib.types.enum [
        "darwin"
        "linux"
        "wsl"
      ];
      description = ''
        ホスト種別。Windows は独立したホストではなく、wsl ホストが /mnt/c に
        設定を書き出す companion レイヤ (nix/modules/wsl/windows/) として扱う。
      '';
    };

    dotfilesDir = lib.mkOption {
      type = lib.types.str;
      description = "この dotfiles リポジトリの clone 先 (mkOutOfStoreSymlink の参照元)。";
    };

    windows = {
      username = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Windows companion のユーザー名 (wsl ホストのみ設定)。";
      };
      homedir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Windows companion のホーム (/mnt/c/Users/... 表記、wsl ホストのみ設定)。";
      };
    };

    # hostKind の派生フラグ (各所での再計算を排除する読み取り専用 option)
    isDarwin = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.hostKind == "darwin";
    };
    isLinux = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.hostKind == "linux";
    };
    isWsl = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.hostKind == "wsl";
    };
  };

  config.assertions = [
    {
      assertion = cfg.hostKind == "wsl" -> (cfg.windows.username != null && cfg.windows.homedir != null);
      message = ''my.hostKind = "wsl" には my.windows.username / my.windows.homedir の設定が必要です'';
    }
  ];
}
