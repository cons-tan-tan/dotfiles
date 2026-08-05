{ features, ... }:
let
  inherit (import ./_lib/gpg.nix) cacheTtl sshKeygrips;
in
{
  features.security-gpg = {
    name = "feature/security/gpg";
    cli-tools = [
      {
        id = "gpg4win";
        winget = {
          packageId = "GnuPG.Gpg4win";
          elevated = true;
          description = "Gpg4win";
        };
      }
    ];
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
    windows =
      { config, lib, ... }:
      let
        pkgs = config._module.args.pkgs;
        agent = pkgs.writeText "windows-gpg-agent.conf" ''
          default-cache-ttl ${toString cacheTtl}
          max-cache-ttl ${toString cacheTtl}
          enable-ssh-support
          pinentry-program C:/Program Files/Gpg4win/bin/pinentry.exe
        '';
        gpgConfig = pkgs.writeText "windows-gpg.conf" ''
          use-agent
        '';
        sshcontrol = pkgs.writeText "windows-sshcontrol" (lib.concatStringsSep "\n" sshKeygrips);
      in
      {
        dotfiles.windows.deployments.gpg = {
          directories = [ "AppData/Roaming/gnupg" ];
          files = [
            {
              source = toString agent;
              destination = "AppData/Roaming/gnupg/gpg-agent.conf";
            }
            {
              source = toString gpgConfig;
              destination = "AppData/Roaming/gnupg/gpg.conf";
            }
            {
              source = toString sshcontrol;
              destination = "AppData/Roaming/gnupg/sshcontrol";
            }
          ];
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
