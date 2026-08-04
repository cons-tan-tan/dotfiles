{
  flake,
  lib,
  pkgs,
  username,
}:
let
  cleanupPolicy = import ../../../../nix/lib/nh-clean-policy.nix;
  cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;
  standaloneLinuxResult = flake.homeConfigurations."${username}@linux-x86_64";
  standaloneLinux = standaloneLinuxResult.config;
  standaloneWsl = flake.homeConfigurations."${username}@wsl-x86_64".config;
  integratedWslSystem = flake.nixosConfigurations.wsl.config;
  integratedWsl = integratedWslSystem.home-manager.users.${username};
  darwinResult = flake.darwinConfigurations.${username};
  darwinSystem = darwinResult.config;
  darwin = darwinSystem.home-manager.users.${username};
  linuxCleanupRunner = standaloneLinuxResult.pkgs.callPackage ../../../../nix/packages/nh-clean-user {
    nh = standaloneLinux.programs.nh.package;
    nix = standaloneLinuxResult.pkgs.nix;
  };
  linuxResultRootPruner =
    standaloneLinuxResult.pkgs.callPackage ../../../../nix/packages/nh-result-root-pruner
      { };
  describePlatform = config: {
    inherit (config.dotfiles.platform)
      environment
      nhCleanupOwner
      standalone
      windowsCompanion
      ;
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
    };
    linuxPackages.drawio = lib.elem standaloneLinuxResult.pkgs.dotfilesPackages.drawio-headless standaloneLinux.home.packages;
    wsl = {
      enable = integratedWslSystem.wsl.enable;
      defaultUser = integratedWslSystem.wsl.defaultUser;
      interop = integratedWslSystem.wsl.interop.register;
      docker = integratedWslSystem.virtualisation.docker.enable;
      stateVersion = integratedWslSystem.system.stateVersion;
    };
  };
  expected = {
    profiles = {
      linux = {
        environment = "linux";
        nhCleanupOwner = "home-manager";
        standalone = true;
        windowsCompanion = false;
      };
      standaloneWsl = {
        environment = "wsl";
        nhCleanupOwner = "switch-app";
        standalone = true;
        windowsCompanion = true;
      };
      integratedWsl = {
        environment = "wsl";
        nhCleanupOwner = "nixos";
        standalone = false;
        windowsCompanion = true;
      };
      darwin = {
        environment = "darwin";
        nhCleanupOwner = "none";
        standalone = false;
        windowsCompanion = false;
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
    };
    linuxPackages.drawio = true;
    wsl = {
      enable = true;
      defaultUser = username;
      interop = true;
      docker = true;
      stateVersion = "26.05";
    };
  };
in
assert lib.assertMsg (actual == expected) ''
  platform feature contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "platform-feature-contract" { } ''touch "$out"''
