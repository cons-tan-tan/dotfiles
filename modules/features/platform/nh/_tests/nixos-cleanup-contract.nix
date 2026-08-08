{
  config,
  entityContext,
  fastNixGc,
  lib,
  pkgs,
}:
let
  username = entityContext.username;
  home = config.home-manager.users.${username};
  cleanupPolicy = import ../_data/cleanup-policy.nix;
  growthChecker = pkgs.callPackage ../_packages/store-growth-checker {
    nix = config.nix.package;
  };
  profileCleanupRunner = pkgs.callPackage ../_packages/clean-user {
    nh = config.programs.nh.package;
    nix = config.nix.package;
    scope = "all";
  };
  storeCleanupRunner = pkgs.callPackage ../_packages/store-cleanup {
    inherit fastNixGc;
    fastNixGcArguments = cleanupPolicy.storeGc.arguments;
    nix = config.nix.package;
    profileCleanup = profileCleanupRunner;
  };
  resultRootPruner = pkgs.callPackage ../_packages/result-root-pruner { };
  growthStatePath = "/var/lib/${cleanupPolicy.growth.stateDirectory}";
  growthRunner = pkgs.callPackage ../_packages/clean-growth-runner {
    checker = growthChecker;
    cleanupCommand = lib.getExe storeCleanupRunner;
    inherit (cleanupPolicy.growth)
      maximumAgeSeconds
      queryTimeout
      retryIntervalSeconds
      thresholdBytes
      ;
  };
  cleanupLock = import ../_interface/cleanup-lock.nix {
    coreutils = pkgs.coreutils;
    inherit lib username;
  };
  flockBin = lib.getExe' pkgs.util-linux "flock";
  contracts = {
    ownership = {
      actual = {
        systemProgramEnabled = config.programs.nh.enable;
        systemCleanupEnabled = config.programs.nh.clean.enable;
        systemUser = config.systemd.services.nh-clean.serviceConfig.User;
        nixGcAutomatic = config.nix.gc.automatic;
        homeProgramEnabled = home.programs.nh.enable;
        homeCleanupEnabled = home.programs.nh.clean.enable;
        homeCleanupServiceDefined = home.systemd.user.services ? nh-clean;
        homeCleanupTimerDefined = home.systemd.user.timers ? nh-clean;
        homeGrowthServiceDefined = home.systemd.user.services ? nh-clean-growth-check;
        homeGrowthTimerDefined = home.systemd.user.timers ? nh-clean-growth-check;
      };
      expected = {
        systemProgramEnabled = false;
        systemCleanupEnabled = false;
        systemUser = "root";
        nixGcAutomatic = false;
        homeProgramEnabled = true;
        homeCleanupEnabled = false;
        homeCleanupServiceDefined = false;
        homeCleanupTimerDefined = false;
        homeGrowthServiceDefined = false;
        homeGrowthTimerDefined = false;
      };
    };
    cleanupPolicy = {
      actual = {
        description = config.systemd.services.nh-clean.description;
        type = config.systemd.services.nh-clean.serviceConfig.Type;
        after = config.systemd.services.nh-clean.after;
        wants = config.systemd.services.nh-clean.wants;
        nice = config.systemd.services.nh-clean.serviceConfig.Nice;
        ioClass = config.systemd.services.nh-clean.serviceConfig.IOSchedulingClass;
        stateDirectory = config.systemd.services.nh-clean.serviceConfig.StateDirectory;
        stateDirectoryMode = config.systemd.services.nh-clean.serviceConfig.StateDirectoryMode;
        lockPreparation = config.systemd.services.nh-clean.serviceConfig.ExecStartPre;
        command = config.systemd.services.nh-clean.serviceConfig.ExecStart;
        timeoutStart = config.systemd.services.nh-clean.serviceConfig.TimeoutStartSec;
        timerOnBoot = config.systemd.timers.nh-clean.timerConfig.OnBootSec;
        timerOnActive = config.systemd.timers.nh-clean.timerConfig.OnUnitActiveSec;
        timerAccuracy = config.systemd.timers.nh-clean.timerConfig.AccuracySec;
        timerWantedBy = config.systemd.timers.nh-clean.wantedBy;
      };
      expected = {
        description = "Clean Nix store after growth or maximum age";
        type = "oneshot";
        after = [ "nix-daemon.socket" ];
        wants = [ "nix-daemon.socket" ];
        nice = 10;
        ioClass = "idle";
        stateDirectory = cleanupPolicy.growth.stateDirectory;
        stateDirectoryMode = "0750";
        lockPreparation = cleanupLock.preparationCommands;
        command = "${flockBin} --exclusive ${cleanupLock.cleanupFile} ${lib.getExe growthRunner} check ${growthStatePath}";
        timeoutStart = cleanupPolicy.growth.cleanupTimeout;
        timerOnBoot = cleanupPolicy.growth.checkInterval;
        timerOnActive = cleanupPolicy.growth.checkInterval;
        timerAccuracy = "30s";
        timerWantedBy = [ "timers.target" ];
      };
    };
    legacyGrowthUnitAbsence = {
      actual = {
        serviceDefined = config.systemd.services ? nh-clean-growth-check;
        timerDefined = config.systemd.timers ? nh-clean-growth-check;
      };
      expected = {
        serviceDefined = false;
        timerDefined = false;
      };
    };
    resultRoots = {
      actual = {
        homeServiceDefined = home.systemd.user.services ? nh-clean-result-roots;
        homeTimerDefined = home.systemd.user.timers ? nh-clean-result-roots;
        systemServiceDefined = config.systemd.services ? nh-clean-result-roots;
        systemTimerDefined = config.systemd.timers ? nh-clean-result-roots;
        user = config.systemd.services.nh-clean-result-roots.serviceConfig.User;
        lockPreparation = config.systemd.services.nh-clean-result-roots.serviceConfig.ExecStartPre;
        command = config.systemd.services.nh-clean-result-roots.serviceConfig.ExecStart;
        calendar = config.systemd.timers.nh-clean-result-roots.timerConfig.OnCalendar;
        persistent = config.systemd.timers.nh-clean-result-roots.timerConfig.Persistent;
      };
      expected = {
        homeServiceDefined = false;
        homeTimerDefined = false;
        systemServiceDefined = true;
        systemTimerDefined = true;
        user = username;
        lockPreparation = cleanupLock.preparationCommands;
        command = "${flockBin} --exclusive ${cleanupLock.cleanupFile} ${lib.getExe resultRootPruner} --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}";
        calendar = cleanupPolicy.resultRoots.dates;
        persistent = true;
      };
    };
  };
  failures = lib.filterAttrs (_: contract: contract.actual != contract.expected) contracts;
in
assert lib.assertMsg (failures == { }) ''
  NixOS NH cleanup contract mismatches:
  ${builtins.toJSON failures}
'';
pkgs.runCommand "nixos-nh-cleanup-contract" { } ''touch "$out"''
