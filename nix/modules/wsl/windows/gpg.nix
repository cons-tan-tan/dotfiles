# Windows companion: Windows 側 gnupg (Gpg4win) の設定を書き出す。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (import ../../../lib/settings/gpg.nix) cacheTtl sshKeygrips;
  deploy = import ./deploy.nix { inherit lib; };

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
  home.activation.deployWindowsGpg = deploy.mkDeployActivation {
    dirs = [ "${windowsHomedir}/AppData/Roaming/gnupg" ];
    files = [
      {
        src = windowsGpgAgentConf;
        dst = "${windowsHomedir}/AppData/Roaming/gnupg/gpg-agent.conf";
      }
      {
        src = windowsGpgConf;
        dst = "${windowsHomedir}/AppData/Roaming/gnupg/gpg.conf";
      }
      {
        src = windowsSshcontrol;
        dst = "${windowsHomedir}/AppData/Roaming/gnupg/sshcontrol";
      }
    ];
  };
}
