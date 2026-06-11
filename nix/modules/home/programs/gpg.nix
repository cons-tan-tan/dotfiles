{
  pkgs,
  lib,
  hostKind,
  windowsHomedir,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  # hostKind は darwin / linux / wsl のみ (Windows companion の設定は
  # windowsGpgAgentConf 以下で別途生成する)。
  pinentryProgram =
    {
      darwin = null; # pinentry_mac は package で指定
      linux = null; # pinentry-curses は package で指定
      wsl = "/mnt/c/Program Files/Gpg4win/bin/pinentry.exe";
    }
    .${hostKind};

  pinentryPackage =
    {
      darwin = {
        package = pkgs.pinentry_mac;
      };
      linux = {
        # package 未指定だと PATH 頼みになり、passphrase 入力が静かに失敗する
        package = pkgs.pinentry-curses;
      };
      wsl = {
        # Windows 側 pinentry.exe を extraConfig (pinentry-program) で指定する
        package = null;
      };
    }
    .${hostKind};

  cacheTtl = 43200;
  sshKeygrips = [
    "60DE257CE1919B3D6DCF4E6E239CD1FFE63B45FD"
  ];

  # Windows companion 用 gpg-agent.conf (Windows native path に固定)
  windowsPinentryProgram = "C:/Program Files/Gpg4win/bin/pinentry.exe";

  windowsGpgAgentConf = pkgs.writeText "windows-gpg-agent.conf" ''
    default-cache-ttl ${toString cacheTtl}
    max-cache-ttl ${toString cacheTtl}
    enable-ssh-support
    pinentry-program ${windowsPinentryProgram}
  '';

  windowsGpgConf = pkgs.writeText "windows-gpg.conf" ''
    use-agent
  '';

  windowsSshcontrol = pkgs.writeText "windows-sshcontrol" (lib.concatStringsSep "\n" sshKeygrips);

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
    pinentry = pinentryPackage;
    extraConfig = lib.optionalString (pinentryProgram != null) ''
      pinentry-program ${pinentryProgram}
    '';
    defaultCacheTtl = cacheTtl;
    maxCacheTtl = cacheTtl;
    sshKeys = sshKeygrips;
  };

  systemd.user.services.set-SSH_AUTH_SOCK.Service.ExecStart = lib.mkIf hk.isWsl (
    lib.mkForce wslSetSshAuthSock
  );

  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsGpg = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      WIN_GNUPGHOME=${windowsHomedir}/AppData/Roaming/gnupg
      run mkdir -p "$WIN_GNUPGHOME"
      run install -m644 ${windowsGpgAgentConf} "$WIN_GNUPGHOME/gpg-agent.conf"
      run install -m644 ${windowsGpgConf} "$WIN_GNUPGHOME/gpg.conf"
      run install -m644 ${windowsSshcontrol} "$WIN_GNUPGHOME/sshcontrol"
    '';
  };
}
