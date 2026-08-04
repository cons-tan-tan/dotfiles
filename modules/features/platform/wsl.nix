{
  features,
  inputs,
  ...
}:
{
  features.platform-wsl-base = {
    name = "feature/platform/wsl/base";
    wsl = {
      # Keep Windows executable interop available when WSL registration is
      # incomplete on the host.
      interop.register = true;

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

  features.platform-wsl-docker = {
    name = "feature/platform/wsl/docker";
    nixos.virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };
  };

  features.platform-wsl-memory = {
    name = "feature/platform/wsl/memory";
    nixos = {
      # Kill the pressured cgroup before the WSL VM exhausts its memory limit.
      systemd.oomd = {
        enable = true;
        enableUserSlices = true;
        settings.OOM.SwapUsedLimit = "80%";
      };
      systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";
      systemd.slices.user.sliceConfig = {
        MemoryAccounting = true;
        MemoryHigh = "24G";
        MemoryMax = "28G";
        MemorySwapMax = "4G";
      };

      # WSL API processes stay under init.scope rather than user.slice.
      systemd.units."init.scope" = {
        overrideStrategy = "asDropin";
        text = ''
          [Scope]
          OOMPolicy=continue
          ManagedOOMPreference=omit
          MemoryHigh=24G
          MemoryMax=28G
          MemorySwapMax=4G
        '';
      };

      # Builders run below nix-daemon and need a separate service boundary.
      systemd.services.nix-daemon.serviceConfig = {
        MemoryAccounting = true;
        MemoryHigh = "20G";
        MemoryMax = "24G";
        MemorySwapMax = "4G";
      };
    };
  };

  features.platform-nix-settings = {
    name = "feature/platform/nix-settings";
    nixos =
      { config, lib, ... }:
      {
        nix.settings =
          (import ../../../nix/lib/nix-custom-settings.nix {
            inherit lib;
            username = config.wsl.defaultUser;
          }).settings
          // {
            experimental-features = [
              "nix-command"
              "flakes"
            ];
          };
      };
  };

  features.platform-wsl = {
    name = "feature/platform/wsl";
    includes = [
      features.platform-context
      features.platform-linux-packages
      features.platform-wsl-base
      features.platform-wsl-docker
      features.platform-wsl-memory
      features.platform-nix-settings
      features.platform-nh
      features.platform-wsl-open
      features.windows-default
    ];
  };
}
