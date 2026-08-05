{ features, ... }:
let
  cleanupPolicy = import ./_data/cleanup-policy.nix;
in
{
  features.platform-nh = {
    name = "feature/platform/nh";

    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        platform = config.dotfiles.platform;
        # Home Manager owns cleanup only for standalone Linux. WSL delegates it
        # to its system or switch app, while Darwin keeps automatic cleanup off.
        enableUserCleanup = platform.environment == "linux" && platform.standalone;
        enableUserResultRootCleanup = enableUserCleanup;
        cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;
        nixPackage =
          if config.nix.enable && config.nix.package != null then config.nix.package else pkgs.nix;
        userCleanupRunner = pkgs.callPackage ./_packages/clean-user {
          nh = config.programs.nh.package;
          nix = nixPackage;
        };
        resultRootPruner = pkgs.callPackage ./_packages/result-root-pruner { };
      in
      {
        programs.nh = {
          enable = true;
          clean = {
            # WSL owns cleanup outside Home Manager; Darwin leaves it disabled.
            enable = enableUserCleanup;
            dates = if platform.environment == "darwin" then "weekly" else cleanupPolicy.dates;
            extraArgs = cleanupArgs;
          };
        };

        systemd.user.services =
          lib.optionalAttrs enableUserResultRootCleanup {
            nh-clean-result-roots = {
              Unit.Description = "Prune stale Nix build result roots";
              Service = {
                Type = "oneshot";
                ExecStart = "${resultRootPruner}/bin/nh-prune-result-roots --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}";
                Nice = 10;
                IOSchedulingClass = "idle";
              };
            };
          }
          // lib.optionalAttrs enableUserCleanup {
            nh-clean.Service = {
              ExecStart = lib.mkForce "${userCleanupRunner}/bin/nh-clean-user";
              Nice = 10;
              IOSchedulingClass = "idle";
            };
          };

        systemd.user.timers = lib.optionalAttrs enableUserResultRootCleanup {
          nh-clean-result-roots = {
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
  };

  features.platform-nh-wsl = {
    name = "feature/platform/nh-wsl";
    includes = [ features.platform-nh ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        growthChecker = pkgs.callPackage ./_packages/store-growth-checker {
          nix = config.nix.package;
        };
        cleanupRunner = pkgs.callPackage ./_packages/clean-user {
          nh = config.programs.nh.package;
          nix = config.nix.package;
          scope = "all";
        };
        resultRootPruner = pkgs.callPackage ./_packages/result-root-pruner { };
        username = config.wsl.defaultUser;
        homedir = config.users.users.${username}.home;
        lock = import ./_interface/cleanup-lock.nix {
          coreutils = pkgs.coreutils;
          inherit lib username;
        };
        growth = cleanupPolicy.growth;
        statePath = "/var/lib/${growth.stateDirectory}";
        growthRunner = pkgs.callPackage ./_packages/clean-growth-runner {
          checker = growthChecker;
          cleanupCommand = lib.getExe cleanupRunner;
          inherit (growth)
            maximumAgeSeconds
            queryTimeout
            retryIntervalSeconds
            thresholdBytes
            ;
        };
      in
      {
        # The system generation owns root cleanup; interactive nh remains HM-owned.
        programs.nh.clean.enable = false;

        systemd.services.nh-clean = {
          description = "Clean Nix store after growth or maximum age";
          after = [ "nix-daemon.socket" ];
          wants = [ "nix-daemon.socket" ];
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Nice = 10;
            IOSchedulingClass = "idle";
            StateDirectory = growth.stateDirectory;
            StateDirectoryMode = "0750";
            ExecStartPre = lock.preparationCommands;
            ExecStart = "${lib.getExe' pkgs.util-linux "flock"} --exclusive ${lock.cleanupFile} ${lib.getExe growthRunner} check ${statePath}";
            TimeoutStartSec = growth.cleanupTimeout;
          };
        };
        systemd.timers.nh-clean = {
          description = "Check Nix store cleanup policy periodically";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = growth.checkInterval;
            OnUnitActiveSec = growth.checkInterval;
            AccuracySec = "30s";
          };
        };

        systemd.services.nh-clean-result-roots = {
          description = "Prune stale Nix build result roots";
          serviceConfig = {
            Type = "oneshot";
            User = username;
            Environment = "HOME=${homedir}";
            WorkingDirectory = homedir;
            Nice = 10;
            IOSchedulingClass = "idle";
            ExecStartPre = lock.preparationCommands;
            ExecStart = "${lib.getExe' pkgs.util-linux "flock"} --exclusive ${lock.cleanupFile} ${lib.getExe resultRootPruner} --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}";
          };
        };
        systemd.timers.nh-clean-result-roots = {
          description = "Weekly cleanup of stale Nix build result roots";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cleanupPolicy.resultRoots.dates;
            Persistent = true;
            RandomizedDelaySec = "30min";
          };
        };

        assertions = [
          {
            assertion = !config.nix.gc.automatic;
            message = "programs.nh.clean and nix.gc.automatic must not run together";
          }
        ];
      };
  };
}
