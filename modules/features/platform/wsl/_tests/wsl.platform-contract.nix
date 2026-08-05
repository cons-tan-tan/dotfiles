{
  integratedWslSystem,
  lib,
  username,
}:
let
  featureNames = [
    "platform-context"
    "drawio-linux-headless"
    "platform-wsl-base"
    "platform-wsl-docker"
    "platform-wsl-memory"
    "platform-nix-settings"
    "platform-nh-wsl"
    "platform-wsl-open"
    "windows-default"
  ];
  featureMarkers = lib.genAttrs featureNames (name: name);
  aggregate =
    (import ../default.nix {
      features = featureMarkers;
    }).features.platform-wsl;
  baseFeature =
    (import ../base.nix {
      inputs.self.outPath = "/fixture/source";
    }).features.platform-wsl-base;
  baseNixos = baseFeature.nixos { inherit lib; };
  dockerFeature = (import ../docker.nix { }).features.platform-wsl-docker;
  memoryFeature = (import ../memory.nix { }).features.platform-wsl-memory;
  nixSettingsFeature =
    (import ../../nix-settings/default.nix {
      den = { };
      inherit lib;
    }).features.platform-nix-settings;
  nixSettings = nixSettingsFeature.nixos {
    config.wsl.defaultUser = username;
    inherit lib;
  };
in
{
  actual = {
    enable = integratedWslSystem.wsl.enable;
    defaultUser = integratedWslSystem.wsl.defaultUser;
    interop = integratedWslSystem.wsl.interop.register;
    docker = integratedWslSystem.virtualisation.docker.enable;
    stateVersion = integratedWslSystem.system.stateVersion;
    aggregate = {
      attributes = builtins.attrNames aggregate;
      includes = aggregate.includes;
      name = aggregate.name;
    };
    independentFeatures = {
      base = {
        attributes = builtins.attrNames baseFeature;
        nixosAttributes = builtins.attrNames baseNixos;
        wslAttributes = builtins.attrNames baseFeature.wsl;
        channelsEnabled = baseNixos.nix.channel.enable;
        gettyTargetWants = baseNixos.systemd.targets.getty.wants.content;
        hostname = baseFeature.wsl.wslConf.network.hostname;
        interop = baseFeature.wsl.interop.register;
        stateVersion = baseNixos.system.stateVersion;
        tarballConfigPath = baseFeature.wsl.tarball.configPath;
        userManagerRetry = {
          restart = baseNixos.systemd.services."user@".serviceConfig.Restart;
          restartSec = baseNixos.systemd.services."user@".serviceConfig.RestartSec;
          startLimitIntervalSec = baseNixos.systemd.services."user@".startLimitIntervalSec;
          startLimitBurst = baseNixos.systemd.services."user@".startLimitBurst;
        };
      };
      docker = {
        attributes = builtins.attrNames dockerFeature;
        nixosAttributes = builtins.attrNames dockerFeature.nixos;
        enable = dockerFeature.nixos.virtualisation.docker.enable;
        enableOnBoot = dockerFeature.nixos.virtualisation.docker.enableOnBoot;
      };
      memory = {
        attributes = builtins.attrNames memoryFeature;
        nixosAttributes = builtins.attrNames memoryFeature.nixos;
        oomd = {
          enable = memoryFeature.nixos.systemd.oomd.enable;
          enableUserSlices = memoryFeature.nixos.systemd.oomd.enableUserSlices;
          swapUsedLimit = memoryFeature.nixos.systemd.oomd.settings.OOM.SwapUsedLimit;
        };
        rootSwapAction = memoryFeature.nixos.systemd.slices."-".sliceConfig.ManagedOOMSwap;
        userSlice = memoryFeature.nixos.systemd.slices.user.sliceConfig;
        initScope = memoryFeature.nixos.systemd.units."init.scope";
        nixDaemon = memoryFeature.nixos.systemd.services.nix-daemon.serviceConfig;
      };
      nixSettings = {
        attributes = builtins.attrNames nixSettingsFeature;
        nixosAttributes = builtins.attrNames nixSettings;
        experimentalFeatures = nixSettings.nix.settings.experimental-features;
        trustedUser = lib.elem username nixSettings.nix.settings.extra-trusted-users;
        minFree = nixSettings.nix.settings.min-free;
        maxFree = nixSettings.nix.settings.max-free;
      };
    };
  };
  expected = {
    enable = true;
    defaultUser = username;
    interop = true;
    docker = true;
    stateVersion = "26.05";
    aggregate = {
      attributes = [
        "includes"
        "name"
      ];
      includes = featureNames;
      name = "feature/platform/wsl";
    };
    independentFeatures = {
      base = {
        attributes = [
          "name"
          "nixos"
          "wsl"
        ];
        nixosAttributes = [
          "nix"
          "system"
          "systemd"
        ];
        wslAttributes = [
          "interop"
          "tarball"
          "wslConf"
        ];
        channelsEnabled = false;
        gettyTargetWants = [ ];
        hostname = "";
        interop = true;
        stateVersion = "26.05";
        tarballConfigPath = "/fixture/source";
        userManagerRetry = {
          restart = "on-failure";
          restartSec = "250ms";
          startLimitIntervalSec = 5;
          startLimitBurst = 5;
        };
      };
      docker = {
        attributes = [
          "name"
          "nixos"
        ];
        nixosAttributes = [ "virtualisation" ];
        enable = true;
        enableOnBoot = true;
      };
      memory = {
        attributes = [
          "name"
          "nixos"
        ];
        nixosAttributes = [ "systemd" ];
        oomd = {
          enable = true;
          enableUserSlices = true;
          swapUsedLimit = "80%";
        };
        rootSwapAction = "kill";
        userSlice = {
          MemoryAccounting = true;
          MemoryHigh = "24G";
          MemoryMax = "28G";
          MemorySwapMax = "4G";
        };
        initScope = {
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
        nixDaemon = {
          MemoryAccounting = true;
          MemoryHigh = "20G";
          MemoryMax = "24G";
          MemorySwapMax = "4G";
        };
      };
      nixSettings = {
        attributes = [
          "name"
          "nixos"
        ];
        nixosAttributes = [ "nix" ];
        experimentalFeatures = [
          "nix-command"
          "flakes"
        ];
        trustedUser = true;
        minFree = 34359738368;
        maxFree = 68719476736;
      };
    };
  };
}
