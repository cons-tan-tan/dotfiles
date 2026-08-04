{ ... }:
let
  inherit (import ../security/_lib/gpg.nix) cacheTtl sshKeygrips;
in
{
  features.windows-gpg = {
    name = "feature/windows/gpg";
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
}
