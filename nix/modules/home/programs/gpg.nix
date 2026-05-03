{
  pkgs,
  lib,
  hostKind,
  windowsHomedir,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  pinentryProgram = {
    darwin = null; # pinentry_mac は package で指定
    linux = null; # X11/curses pinentry を使う場合は別途設定
    wsl = "/mnt/c/Program Files/Gpg4win/bin/pinentry.exe";
    windows = "C:/Program Files/Gpg4win/bin/pinentry.exe";
  }.${hostKind};

  pinentryPackage = {
    darwin = { package = pkgs.pinentry_mac; };
    linux = { package = null; };
    wsl = { package = null; };
    windows = null;
  }.${hostKind};

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
