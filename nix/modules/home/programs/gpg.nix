{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (import ../../../lib/settings/gpg.nix) cacheTtl sshKeygrips;

  # Windows companion の gpg 設定は modules/wsl/windows/gpg.nix で別途生成する。
  pinentry =
    {
      darwin = {
        program = null;
        package = pkgs.pinentry_mac;
      };
      linux = {
        # package 未指定だと PATH 頼みになり、passphrase 入力が静かに失敗する
        program = null;
        package = pkgs.pinentry-curses;
      };
      wsl = {
        # Windows 側 pinentry.exe を extraConfig (pinentry-program) で指定する
        program = "/mnt/c/Program Files/Gpg4win/bin/pinentry.exe";
        package = null;
      };
    }
    .${config.my.hostKind};

  wslSetSshAuthSock = pkgs.writeShellScript "set-SSH_AUTH_SOCK-wsl" ''
    if [ -z "''${SSH_AUTH_SOCK:-}" ] || [ -z "''${SSH_CONNECTION:-}" ]; then
      unset SSH_AGENT_PID
      if [ "''${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
        export SSH_AUTH_SOCK="$(${pkgs.gnupg}/bin/gpgconf --list-dirs agent-ssh-socket)"
      fi
    fi

    ${pkgs.systemd}/bin/systemctl --user import-environment SSH_AUTH_SOCK
  '';
in
{
  programs.gpg = {
    enable = true;
    package = pkgs.gnupg;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry = {
      inherit (pinentry) package;
    };
    extraConfig = lib.optionalString (pinentry.program != null) ''
      pinentry-program ${pinentry.program}
    '';
    defaultCacheTtl = cacheTtl;
    maxCacheTtl = cacheTtl;
    sshKeys = sshKeygrips;
  };

  systemd.user.services.set-SSH_AUTH_SOCK.Service.ExecStart = lib.mkIf config.my.isWsl (
    lib.mkForce wslSetSshAuthSock
  );
}
