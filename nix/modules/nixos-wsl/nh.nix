{
  config,
  lib,
  pkgs,
  ...
}:
let
  cleanupPolicy = import ../../lib/nh-clean-policy.nix;
  growthChecker = pkgs.callPackage ../../packages/nix-store-growth-checker {
    nix = config.nix.package;
  };
  cleanupRunner = pkgs.callPackage ../../packages/nh-clean-user {
    nh = config.programs.nh.package;
    nix = config.nix.package;
    scope = "all";
  };
  resultRootPruner = pkgs.callPackage ../../packages/nh-result-root-pruner { };
  username = config.wsl.defaultUser;
  homedir = config.users.users.${username}.home;
  growth = cleanupPolicy.growth;
  statePath = "/var/lib/${growth.stateDirectory}";
  growthRunner = pkgs.callPackage ../../packages/nh-clean-growth-runner {
    checker = growthChecker;
    cleanupCommand = lib.getExe cleanupRunner;
    inherit (growth)
      maximumAgeSeconds
      queryTimeout
      retryIntervalSeconds
      thresholdBytes
      ;
  };
  growthRunnerBin = lib.getExe growthRunner;
in
{
  # The system generation is root-owned, so this system service uses
  # `nh clean all`; interactive nh remains Home Manager-managed.
  programs.nh.clean = {
    enable = false;
  };

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
      ExecStart = "${growthRunnerBin} check ${statePath}";
      TimeoutStartSec = growth.cleanupTimeout;
    };
  };

  # The frequent timer only wakes the shared policy checker. Cleanup succeeds
  # when either limit is reached, then atomically resets both policy baselines.
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
      ExecStart = "${lib.getExe resultRootPruner} --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}";
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
}
