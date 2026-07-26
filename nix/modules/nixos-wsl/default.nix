{
  lib,
  pkgs,
  username,
  ...
}:
{
  wsl = {
    enable = true;
    defaultUser = username;

    # WSL側の自動登録が欠ける環境でもWindows実行ファイルを起動できるようにする。
    interop.register = true;

    # 暫定対応: 別distroとのsystemd cgroup共有によるuser sessionの衝突を避けるため、
    # microsoft/WSL#40519を含むreleaseが利用可能になるまではhostnameを省略する。
    # 更新後に同じUIDの複数distroで再発しないことを確認し、この上書きを削除する。
    # https://github.com/nix-community/NixOS-WSL/issues/888
    # https://github.com/microsoft/WSL/pull/40519
    wslConf.network.hostname = "";
  };

  # 非対話の WSL 起動でも user manager を常駐させ、nixos-rebuild が
  # Home Manager の user units を再読込できるようにする。
  users.users.${username} = {
    linger = true;
    extraGroups = [ "docker" ];
    shell = pkgs.zsh;
  };

  # WSLではUbuntu由来のbash設定を引き継がず、Home Manager管理のzshへ移行する。
  programs.zsh.enable = true;

  # Docker Desktopに依存せず、LinuxコンテナをNixOS内で完結させる。
  # Docker APIはTCP公開せず、ローカルのUnix socketをdocker groupから利用する。
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # WSLのセッションはLinux VT1を使わない。nixpkgsがgetty.targetから起動する
  # autovt@tty1はWSL上で再起動を繰り返し、switchを失敗扱いにするため、
  # getty自体は残したまま自動起動だけを外す。
  # https://github.com/NixOS/nixpkgs/pull/428972
  systemd.targets.getty.wants = lib.mkForce [ ];

  # 暫定対応: WSL起動直後はuser@.serviceのexecutor spawnがEBUSYで失敗するため、
  # user managerだけを短時間で再試行する。microsoft/WSL#40519を含むreleaseへ
  # 更新後に再試行なしで起動できることを確認し、このuser@ overrideを削除する。
  # https://github.com/nix-community/NixOS-WSL/issues/888
  # https://github.com/microsoft/WSL/pull/40519
  systemd.services."user@" = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "250ms";
    };
    startLimitIntervalSec = 5;
    startLimitBurst = 5;
  };

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
