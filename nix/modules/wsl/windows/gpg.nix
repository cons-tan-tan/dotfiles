# Windows companion: Windows 側 gnupg (Gpg4win) の設定を書き出す。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (import ../../../lib/settings/gpg.nix) cacheTtl sshKeygrips;

  windowsHomedir = config.my.windows.homedir;

  # Windows native path に固定
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
in
{
  home.activation.deployWindowsGpg = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WIN_GNUPGHOME="${windowsHomedir}/AppData/Roaming/gnupg"
    run mkdir -p "$WIN_GNUPGHOME"
    run install -m644 "${windowsGpgAgentConf}" "$WIN_GNUPGHOME/gpg-agent.conf"
    run install -m644 "${windowsGpgConf}" "$WIN_GNUPGHOME/gpg.conf"
    run install -m644 "${windowsSshcontrol}" "$WIN_GNUPGHOME/sshcontrol"
  '';
}
