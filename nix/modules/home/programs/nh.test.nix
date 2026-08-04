{
  homeManager,
  lib,
  pkgs,
}:
let
  cleanupPolicy = import ../../../lib/nh-clean-policy.nix;
  cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;

  mkEvaluatedConfig =
    {
      isLinux ? false,
      isWsl ? false,
      osConfig ? null,
      standalone ? true,
    }:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit osConfig; };
      modules = [
        ./nh.nix
        (
          { lib, ... }:
          {
            options.my = {
              isLinux = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              isWsl = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              standalone = lib.mkOption {
                type = lib.types.bool;
              };
            };

            config = {
              my = {
                inherit isLinux isWsl standalone;
              };
              home = {
                username = "test";
                homeDirectory = "/home/test";
                stateVersion = "24.11";
              };
            };
          }
        )
      ];
    }).config;

  evaluatedLinux = mkEvaluatedConfig { isLinux = true; };
  evaluatedWsl = mkEvaluatedConfig { isWsl = true; };
  evaluatedIntegratedWsl = mkEvaluatedConfig {
    isWsl = true;
    osConfig = { };
    standalone = false;
  };
  evaluatedStandaloneLinuxWithOsConfig = mkEvaluatedConfig {
    isLinux = true;
    osConfig = { };
    standalone = true;
  };
  evaluatedIntegratedLinuxWithoutOsConfig = mkEvaluatedConfig {
    isLinux = true;
    standalone = false;
  };
  evaluatedDarwin = mkEvaluatedConfig { };

  expectedCleanup = {
    enable = true;
    dates = cleanupPolicy.dates;
    extraArgs = cleanupArgs;
  };
  expectedDisabledSystemCleanup = expectedCleanup // {
    enable = false;
  };
  expectedDarwinCleanup = expectedDisabledSystemCleanup // {
    dates = "weekly";
  };
  resultRootPruner = pkgs.callPackage ../../../packages/nh-result-root-pruner { };
  expectedCleanupRunner = pkgs.callPackage ../../../packages/nh-clean-user {
    nh = evaluatedLinux.programs.nh.package;
    nix = pkgs.nix;
  };
  expectedResultRootService = {
    Unit.Description = "Prune stale Nix build result roots";
    Service = {
      Type = "oneshot";
      ExecStart = "${resultRootPruner}/bin/nh-prune-result-roots --keep-minutes ${toString cleanupPolicy.resultRoots.keepMinutes}";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  expectedResultRootTimer = {
    Unit.Description = "Weekly cleanup of stale Nix build result roots";
    Timer = {
      OnCalendar = cleanupPolicy.resultRoots.dates;
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  finalRegularService =
    evaluated:
    let
      inherit (evaluated.systemd.user.services.nh-clean) Service;
    in
    {
      inherit (Service)
        Environment
        ExecStart
        IOSchedulingClass
        Nice
        ;
    };
  finalRegularTimer =
    evaluated:
    let
      inherit (evaluated.systemd.user.timers.nh-clean) Install Timer;
    in
    {
      inherit (Install) WantedBy;
      inherit (Timer) OnCalendar Persistent;
    };
  finalResultRootUnit =
    evaluated:
    let
      service = evaluated.systemd.user.services.nh-clean-result-roots;
      timer = evaluated.systemd.user.timers.nh-clean-result-roots;
    in
    {
      service = {
        Unit.Description = service.Unit.Description;
        Service = {
          inherit (service.Service)
            ExecStart
            IOSchedulingClass
            Nice
            Type
            ;
        };
      };
      timer = {
        Unit.Description = timer.Unit.Description;
        inherit (timer) Install Timer;
      };
    };
  expectedFinalRegularService = {
    Environment = [ ];
    ExecStart = [ "${expectedCleanupRunner}/bin/nh-clean-user" ];
    IOSchedulingClass = "idle";
    Nice = 10;
  };
  expectedFinalRegularTimer = {
    OnCalendar = cleanupPolicy.dates;
    Persistent = true;
    WantedBy = [ "timers.target" ];
  };
  expectedFinalResultRootUnit = {
    service = expectedResultRootService // {
      Service = expectedResultRootService.Service // {
        ExecStart = [ expectedResultRootService.Service.ExecStart ];
      };
    };
    timer = expectedResultRootTimer;
  };
  systemdPlatformTest =
    test:
    if pkgs.stdenv.hostPlatform.isLinux then
      test
    else
      {
        expr = true;
        expected = true;
      };
in
{
  testLinuxUsesBoundedCleanupPolicy = systemdPlatformTest {
    expr = evaluatedLinux.programs.nh.clean;
    expected = expectedCleanup;
  };

  testWslUsesBoundedCleanupPolicy = systemdPlatformTest {
    expr = evaluatedWsl.programs.nh.clean;
    expected = expectedDisabledSystemCleanup;
  };

  testLinuxCleanupUsesStoreClosedRunner = systemdPlatformTest {
    expr = finalRegularService evaluatedLinux;
    expected = expectedFinalRegularService;
  };

  testLinuxFinalCleanupTimer = systemdPlatformTest {
    expr = finalRegularTimer evaluatedLinux;
    expected = expectedFinalRegularTimer;
  };

  testStandaloneWslLeavesCleanupToSystemUnits = systemdPlatformTest {
    expr = {
      hasCleanupService = evaluatedWsl.systemd.user.services ? nh-clean;
      hasCleanupTimer = evaluatedWsl.systemd.user.timers ? nh-clean;
      hasGrowthService = evaluatedWsl.systemd.user.services ? nh-clean-growth-check;
      hasGrowthTimer = evaluatedWsl.systemd.user.timers ? nh-clean-growth-check;
      hasResultRootService = evaluatedWsl.systemd.user.services ? nh-clean-result-roots;
      hasResultRootTimer = evaluatedWsl.systemd.user.timers ? nh-clean-result-roots;
    };
    expected = {
      hasCleanupService = false;
      hasCleanupTimer = false;
      hasGrowthService = false;
      hasGrowthTimer = false;
      hasResultRootService = false;
      hasResultRootTimer = false;
    };
  };

  testIntegratedWslDelegatesCleanupToNixos = systemdPlatformTest {
    expr = {
      clean = evaluatedIntegratedWsl.programs.nh.clean;
      hasUserCleanupService = evaluatedIntegratedWsl.systemd.user.services ? nh-clean;
      hasUserCleanupTimer = evaluatedIntegratedWsl.systemd.user.timers ? nh-clean;
      hasResultRootService = evaluatedIntegratedWsl.systemd.user.services ? nh-clean-result-roots;
      hasResultRootTimer = evaluatedIntegratedWsl.systemd.user.timers ? nh-clean-result-roots;
      hasGrowthService = evaluatedIntegratedWsl.systemd.user.services ? nh-clean-growth-check;
      hasGrowthTimer = evaluatedIntegratedWsl.systemd.user.timers ? nh-clean-growth-check;
    };
    expected = {
      clean = expectedDisabledSystemCleanup;
      hasUserCleanupService = false;
      hasUserCleanupTimer = false;
      hasResultRootService = false;
      hasResultRootTimer = false;
      hasGrowthService = false;
      hasGrowthTimer = false;
    };
  };

  testCleanupOwnershipUsesStandaloneMetadata = systemdPlatformTest {
    expr = {
      standaloneWithOsConfig = {
        clean = evaluatedStandaloneLinuxWithOsConfig.programs.nh.clean.enable;
        hasCleanupService = evaluatedStandaloneLinuxWithOsConfig.systemd.user.services ? nh-clean;
      };
      integratedWithoutOsConfig = {
        clean = evaluatedIntegratedLinuxWithoutOsConfig.programs.nh.clean.enable;
        hasCleanupService = evaluatedIntegratedLinuxWithoutOsConfig.systemd.user.services ? nh-clean;
      };
    };
    expected = {
      standaloneWithOsConfig = {
        clean = true;
        hasCleanupService = true;
      };
      integratedWithoutOsConfig = {
        clean = false;
        hasCleanupService = false;
      };
    };
  };

  testLinuxFinalResultRootUnits = systemdPlatformTest {
    expr = finalResultRootUnit evaluatedLinux;
    expected = expectedFinalResultRootUnit;
  };

  testDarwinDoesNotDefineSystemdCleanup = {
    expr = {
      inherit (evaluatedDarwin.systemd.user) services timers;
    };
    expected = {
      services = { };
      timers = { };
    };
  };

  testDarwinLeavesCleanupToDeterminateNix = {
    expr = evaluatedDarwin.programs.nh.clean;
    expected = expectedDarwinCleanup;
  };
}
