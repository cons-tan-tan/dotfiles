{
  lib,
  username,
  ...
}:
{
  wsl = {
    enable = true;
    defaultUser = username;

    # WSL側の自動登録が欠ける環境でもWindows実行ファイルを起動できるようにする。
    interop.register = true;
  };

  # 非対話の WSL 起動でも user manager を常駐させ、nixos-rebuild が
  # Home Manager の user units を再読込できるようにする。
  users.users.${username}.linger = true;

  # NixOSではdaemon設定もsystem generationへ含め、Ubuntu向けの
  # apply-nix-settingsによる可変な/etc/nix更新を不要にする。
  nix.settings =
    (import ../../lib/nix-custom-settings.nix {
      inherit lib username;
    }).settings
    // {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

  # 新規に作るNixOS-WSLイメージの互換性基準。更新時に自動で上げないこと。
  system.stateVersion = "26.05";
}
