{ features, ... }:
let
  inherit (import ./_lib/gpg.nix) cacheTtl sshKeygrips;
in
{
  features.security-gpg = {
    name = "feature/security/gpg";
    homeManager = { pkgs, ... }: {
      programs.gpg = {
        enable = true;
        package = pkgs.gnupg;
      };
      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
        defaultCacheTtl = cacheTtl;
        maxCacheTtl = cacheTtl;
        sshKeys = sshKeygrips;
      };
    };
  };

  features.security-gpg-linux = {
    name = "feature/security/gpg/linux";
    includes = [ features.security-gpg ];
    homeManager = { pkgs, ... }: {
      services.gpg-agent.pinentry.package = pkgs.pinentry-curses;
    };
  };

  features.security-gpg-wsl = {
    name = "feature/security/gpg/wsl";
    includes = [ features.security-gpg ];
    homeManager =
      { lib, pkgs, ... }:
      {
        services.gpg-agent = {
          pinentry.package = null;
          extraConfig = ''
            pinentry-program /mnt/c/Program Files/Gpg4win/bin/pinentry.exe
          '';
        };
        systemd.user.services.set-SSH_AUTH_SOCK.Service.ExecStart = lib.mkForce (
          lib.getExe pkgs.dotfilesPackages.wsl-set-ssh-auth-sock
        );
      };
  };

  features.security-gpg-darwin = {
    name = "feature/security/gpg/darwin";
    includes = [ features.security-gpg ];
    homeManager = { pkgs, ... }: {
      services.gpg-agent.pinentry.package = pkgs.pinentry_mac;
    };
  };
}
