{
  entityContexts,
  flake,
  lib,
  pkgs,
}:
let
  username = "constantan";
  subjectUsername = entityContexts.linuxX86.username;
  cleanupPolicy = import ../lib/nh-clean-policy.nix;
  cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;
  standaloneLinuxResult = flake.homeConfigurations.${entityContexts.linuxX86.home.linux};
  standaloneLinux = standaloneLinuxResult.config;
  standaloneWsl = flake.homeConfigurations.${entityContexts.linuxX86.home.wsl}.config;
  integratedWslSystem = flake.nixosConfigurations.${entityContexts.linuxX86.nixosWsl}.config;
  integratedWsl = integratedWslSystem.home-manager.users.${subjectUsername};
  darwinResult = flake.darwinConfigurations.${entityContexts.darwin.darwin};
  darwinSystem = darwinResult.config;
  darwin = darwinSystem.home-manager.users.${entityContexts.darwin.username};
  darwinFontsContribution =
    (import ../../modules/features/platform/darwin/fonts.nix { }).features.platform-darwin-fonts.darwin
      { pkgs = darwinResult.pkgs; };
  darwinTouchIdFeature =
    (import ../../modules/features/platform/darwin/touch-id.nix { }).features.platform-darwin-touch-id;
  darwinTouchIdContribution = darwinTouchIdFeature.darwin;
  darwinFeatureNames = [
    "platform-context"
    "platform-darwin-system"
    "platform-darwin-fonts"
    "platform-darwin-touch-id"
    "platform-homebrew"
    "platform-darwin-packages"
    "platform-ghostty"
    "platform-sleepctl"
    "platform-nh"
  ];
  darwinFeatureMarkers = lib.genAttrs darwinFeatureNames (name: name);
  darwinAggregate =
    (import ../../modules/features/platform/darwin/default.nix {
      features = darwinFeatureMarkers;
    }).features.platform-darwin;
  wslFeatureNames = [
    "platform-context"
    "platform-linux-packages"
    "platform-wsl-base"
    "platform-wsl-docker"
    "platform-wsl-memory"
    "platform-nix-settings"
    "platform-nh"
    "platform-wsl-open"
    "windows-default"
  ];
  wslFeatureMarkers = lib.genAttrs wslFeatureNames (name: name);
  wslAggregate =
    (import ../../modules/features/platform/wsl/default.nix {
      features = wslFeatureMarkers;
    }).features.platform-wsl;
  wslBaseFeature =
    (import ../../modules/features/platform/wsl/base.nix {
      inputs.self.outPath = "/fixture/source";
    }).features.platform-wsl-base;
  wslBaseNixos = wslBaseFeature.nixos { inherit lib; };
  wslDockerFeature =
    (import ../../modules/features/platform/wsl/docker.nix { }).features.platform-wsl-docker;
  wslMemoryFeature =
    (import ../../modules/features/platform/wsl/memory.nix { }).features.platform-wsl-memory;
  wslNixSettingsFeature =
    (import ../../modules/features/platform/wsl/nix-settings.nix { }).features.platform-nix-settings;
  wslNixSettings = wslNixSettingsFeature.nixos {
    config.wsl.defaultUser = username;
    inherit lib;
  };
  linuxCleanupRunner = standaloneLinuxResult.pkgs.callPackage ../packages/nh-clean-user {
    nh = standaloneLinux.programs.nh.package;
    nix = standaloneLinuxResult.pkgs.nix;
  };
  linuxResultRootPruner =
    standaloneLinuxResult.pkgs.callPackage ../packages/nh-result-root-pruner
      { };
  describePlatform = config: {
    inherit (config.dotfiles.platform)
      environment
      nhCleanupOwner
      standalone
      ;
    inherit (config.dotfiles.platform) windows;
  };
  actual = {
    profiles = {
      linux = describePlatform standaloneLinux;
      standaloneWsl = describePlatform standaloneWsl;
      integratedWsl = describePlatform integratedWsl;
      darwin = describePlatform darwin;
    };
    cleanup = {
      linux = {
        clean = standaloneLinux.programs.nh.clean;
        service = {
          inherit (standaloneLinux.systemd.user.services.nh-clean.Service)
            Environment
            ExecStart
            IOSchedulingClass
            Nice
            ;
        };
        timer = {
          inherit (standaloneLinux.systemd.user.timers.nh-clean.Install) WantedBy;
          inherit (standaloneLinux.systemd.user.timers.nh-clean.Timer) OnCalendar Persistent;
        };
        resultRoots = {
          service = {
            Unit.Description = standaloneLinux.systemd.user.services.nh-clean-result-roots.Unit.Description;
            Service = {
              inherit (standaloneLinux.systemd.user.services.nh-clean-result-roots.Service)
                ExecStart
                IOSchedulingClass
                Nice
                Type
                ;
            };
          };
          timer = {
            Unit.Description = standaloneLinux.systemd.user.timers.nh-clean-result-roots.Unit.Description;
            inherit (standaloneLinux.systemd.user.timers.nh-clean-result-roots) Install Timer;
          };
        };
      };
      standaloneWsl = {
        clean = standaloneWsl.programs.nh.clean.enable;
        service = standaloneWsl.systemd.user.services ? nh-clean;
        resultRoots = standaloneWsl.systemd.user.services ? nh-clean-result-roots;
      };
      integratedWsl = {
        homeClean = integratedWsl.programs.nh.clean.enable;
        homeService = integratedWsl.systemd.user.services ? nh-clean;
        systemService = integratedWslSystem.systemd.services ? nh-clean;
        systemTimer = integratedWslSystem.systemd.timers ? nh-clean;
        resultRoots = integratedWslSystem.systemd.services ? nh-clean-result-roots;
      };
      darwin = {
        clean = darwin.programs.nh.clean.enable;
        nixEnabled = darwinSystem.nix.enable;
      };
    };
    darwin = {
      inherit (darwinSystem.system) primaryUser stateVersion;
      sleepctlArguments = darwinSystem.launchd.daemons.sleepctld.serviceConfig.ProgramArguments;
      sleepctlLifecycle = {
        inherit (darwinSystem.launchd.daemons.sleepctld.serviceConfig)
          KeepAlive
          ProcessType
          RunAtLoad
          ThrottleInterval
          ;
        userName = darwinSystem.launchd.daemons.sleepctld.serviceConfig.UserName or null;
      };
      ghostty = darwin.programs.ghostty.enable;
      homebrew = darwinSystem.homebrew.enable;
      packages = {
        codexApp = lib.elem darwinResult.pkgs.dotfilesPackages.codex-app darwin.home.packages;
        raycast = lib.elem darwinResult.pkgs.raycast darwin.home.packages;
        zed = lib.elem darwinResult.pkgs.brewCasks.zed darwin.home.packages;
      };
      independentFeatures = {
        aggregate = {
          hackgen = lib.elem darwinResult.pkgs.hackgen-nf-font darwinSystem.fonts.packages;
          symbols = lib.elem darwinResult.pkgs.nerd-fonts.symbols-only darwinSystem.fonts.packages;
          touchId = darwinSystem.security.pam.services.sudo_local.touchIdAuth;
        };
        fontsOnly = {
          hackgen = lib.elem darwinResult.pkgs.hackgen-nf-font darwinFontsContribution.fonts.packages;
          symbols = lib.elem darwinResult.pkgs.nerd-fonts.symbols-only darwinFontsContribution.fonts.packages;
          ownsTouchId = darwinFontsContribution ? security;
        };
        touchIdOnly = {
          enabled = darwinTouchIdContribution.security.pam.services.sudo_local.touchIdAuth;
          name = darwinTouchIdFeature.name;
        };
      };
      aggregate = {
        attributes = builtins.attrNames darwinAggregate;
        includes = darwinAggregate.includes;
        name = darwinAggregate.name;
      };
    };
    linuxPackages.drawio = lib.elem standaloneLinuxResult.pkgs.dotfilesPackages.drawio-headless standaloneLinux.home.packages;
    wsl = {
      enable = integratedWslSystem.wsl.enable;
      defaultUser = integratedWslSystem.wsl.defaultUser;
      interop = integratedWslSystem.wsl.interop.register;
      docker = integratedWslSystem.virtualisation.docker.enable;
      stateVersion = integratedWslSystem.system.stateVersion;
      aggregate = {
        attributes = builtins.attrNames wslAggregate;
        includes = wslAggregate.includes;
        name = wslAggregate.name;
      };
      independentFeatures = {
        base = {
          attributes = builtins.attrNames wslBaseFeature;
          nixosAttributes = builtins.attrNames wslBaseNixos;
          wslAttributes = builtins.attrNames wslBaseFeature.wsl;
          channelsEnabled = wslBaseNixos.nix.channel.enable;
          gettyTargetWants = wslBaseNixos.systemd.targets.getty.wants.content;
          hostname = wslBaseFeature.wsl.wslConf.network.hostname;
          interop = wslBaseFeature.wsl.interop.register;
          stateVersion = wslBaseNixos.system.stateVersion;
          tarballConfigPath = wslBaseFeature.wsl.tarball.configPath;
          userManagerRetry = {
            restart = wslBaseNixos.systemd.services."user@".serviceConfig.Restart;
            restartSec = wslBaseNixos.systemd.services."user@".serviceConfig.RestartSec;
            startLimitIntervalSec = wslBaseNixos.systemd.services."user@".startLimitIntervalSec;
            startLimitBurst = wslBaseNixos.systemd.services."user@".startLimitBurst;
          };
        };
        docker = {
          attributes = builtins.attrNames wslDockerFeature;
          nixosAttributes = builtins.attrNames wslDockerFeature.nixos;
          enable = wslDockerFeature.nixos.virtualisation.docker.enable;
          enableOnBoot = wslDockerFeature.nixos.virtualisation.docker.enableOnBoot;
        };
        memory = {
          attributes = builtins.attrNames wslMemoryFeature;
          nixosAttributes = builtins.attrNames wslMemoryFeature.nixos;
          oomd = {
            enable = wslMemoryFeature.nixos.systemd.oomd.enable;
            enableUserSlices = wslMemoryFeature.nixos.systemd.oomd.enableUserSlices;
            swapUsedLimit = wslMemoryFeature.nixos.systemd.oomd.settings.OOM.SwapUsedLimit;
          };
          rootSwapAction = wslMemoryFeature.nixos.systemd.slices."-".sliceConfig.ManagedOOMSwap;
          userSlice = wslMemoryFeature.nixos.systemd.slices.user.sliceConfig;
          initScope = wslMemoryFeature.nixos.systemd.units."init.scope";
          nixDaemon = wslMemoryFeature.nixos.systemd.services.nix-daemon.serviceConfig;
        };
        nixSettings = {
          attributes = builtins.attrNames wslNixSettingsFeature;
          nixosAttributes = builtins.attrNames wslNixSettings;
          experimentalFeatures = wslNixSettings.nix.settings.experimental-features;
          trustedUser = lib.elem username wslNixSettings.nix.settings.extra-trusted-users;
          minFree = wslNixSettings.nix.settings.min-free;
          maxFree = wslNixSettings.nix.settings.max-free;
        };
      };
    };
  };
  expected = {
    profiles = {
      linux = {
        environment = "linux";
        nhCleanupOwner = "home-manager";
        standalone = true;
        windows = {
          enable = false;
          username = null;
          homedir = null;
        };
      };
      standaloneWsl = {
        environment = "wsl";
        nhCleanupOwner = "switch-app";
        standalone = true;
        windows = {
          enable = true;
          username = "zhouc";
          homedir = "/mnt/c/Users/zhouc";
        };
      };
      integratedWsl = {
        environment = "wsl";
        nhCleanupOwner = "nixos";
        standalone = false;
        windows = {
          enable = true;
          username = "zhouc";
          homedir = "/mnt/c/Users/zhouc";
        };
      };
      darwin = {
        environment = "darwin";
        nhCleanupOwner = "none";
        standalone = false;
        windows = {
          enable = false;
          username = null;
          homedir = null;
        };
      };
    };
    cleanup = {
      linux = {
        clean = {
          enable = true;
          dates = cleanupPolicy.dates;
          extraArgs = cleanupArgs;
        };
        service = {
          Environment = [ ];
          ExecStart = [ "${linuxCleanupRunner}/bin/nh-clean-user" ];
          IOSchedulingClass = "idle";
          Nice = 10;
        };
        timer = {
          OnCalendar = cleanupPolicy.dates;
          Persistent = true;
          WantedBy = [ "timers.target" ];
        };
        resultRoots = {
          service = {
            Unit.Description = "Prune stale Nix build result roots";
            Service = {
              Type = "oneshot";
              ExecStart = [
                "${linuxResultRootPruner}/bin/nh-prune-result-roots --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}"
              ];
              Nice = 10;
              IOSchedulingClass = "idle";
            };
          };
          timer = {
            Unit.Description = "Weekly cleanup of stale Nix build result roots";
            Timer = {
              OnCalendar = cleanupPolicy.resultRoots.dates;
              Persistent = true;
              RandomizedDelaySec = "30min";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
      standaloneWsl = {
        clean = false;
        service = false;
        resultRoots = false;
      };
      integratedWsl = {
        homeClean = false;
        homeService = false;
        systemService = true;
        systemTimer = true;
        resultRoots = true;
      };
      darwin = {
        clean = false;
        nixEnabled = false;
      };
    };
    darwin = {
      primaryUser = username;
      stateVersion = 5;
      sleepctlArguments = [
        "${darwinResult.pkgs.dotfilesPackages.sleepctl}/bin/sleepctld"
        "--allowed-user"
        username
      ];
      sleepctlLifecycle = {
        KeepAlive = true;
        ProcessType = "Background";
        RunAtLoad = true;
        ThrottleInterval = 5;
        userName = null;
      };
      ghostty = true;
      homebrew = true;
      packages = {
        codexApp = true;
        raycast = true;
        zed = true;
      };
      independentFeatures = {
        aggregate = {
          hackgen = true;
          symbols = true;
          touchId = true;
        };
        fontsOnly = {
          hackgen = true;
          symbols = true;
          ownsTouchId = false;
        };
        touchIdOnly = {
          enabled = true;
          name = "feature/platform/darwin/touch-id";
        };
      };
      aggregate = {
        attributes = [
          "includes"
          "name"
        ];
        includes = darwinFeatureNames;
        name = "feature/platform/darwin";
      };
    };
    linuxPackages.drawio = true;
    wsl = {
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
        includes = wslFeatureNames;
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
  };
in
assert lib.assertMsg (actual == expected) ''
  platform feature contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "platform-feature-contract" { } ''touch "$out"''
