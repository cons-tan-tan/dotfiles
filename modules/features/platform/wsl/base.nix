{ inputs, ... }:
{
  features.platform-wsl-base = {
    name = "feature/platform/wsl/base";
    wsl = {
      # Let WSL own WSLInterop. Adding NixOS binfmt registrations activates
      # systemd-binfmt, whose bulk flush conflicts with WSL's protected status.
      # https://github.com/microsoft/WSL/pull/40621

      # microsoft/WSL#40519 must be present before restoring a hostname here;
      # shared systemd cgroups otherwise collide across distros with the same UID.
      # https://github.com/nix-community/NixOS-WSL/issues/888
      # https://github.com/microsoft/WSL/pull/40519
      wslConf.network.hostname = "";

      # Keep a flake snapshot in generated tarballs for recovery before the
      # canonical clone exists.
      tarball.configPath = inputs.self.outPath;
    };
    nixos = { lib, ... }: {
      nix.channel.enable = false;

      # WSL never uses Linux VT1. autovt@tty1 otherwise restart-loops and can
      # make a successful switch appear failed.
      # https://github.com/NixOS/nixpkgs/pull/428972
      systemd.targets.getty.wants = lib.mkForce [ ];

      # WSL startup can transiently return EBUSY while spawning user@.service.
      # Remove after microsoft/WSL#40519 is deployed and retested without retry.
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

      # Compatibility baseline for newly generated NixOS-WSL images.
      system.stateVersion = "26.05";
    };
  };
}
