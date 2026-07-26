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
            };

            config = {
              my = {
                inherit isLinux isWsl;
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
    expected = expectedCleanup;
  };

  testLinuxCleanupUsesStoreClosedRunner = systemdPlatformTest {
    expr = finalRegularService evaluatedLinux;
    expected = expectedFinalRegularService;
  };

  testWslCleanupUsesStoreClosedRunner = systemdPlatformTest {
    expr = finalRegularService evaluatedWsl;
    expected = expectedFinalRegularService;
  };

  testLinuxFinalCleanupTimer = systemdPlatformTest {
    expr = finalRegularTimer evaluatedLinux;
    expected = expectedFinalRegularTimer;
  };

  testWslFinalCleanupTimer = systemdPlatformTest {
    expr = finalRegularTimer evaluatedWsl;
    expected = expectedFinalRegularTimer;
  };

  testIntegratedWslDelegatesCleanupToNixos = systemdPlatformTest {
    expr = {
      clean = evaluatedIntegratedWsl.programs.nh.clean;
      hasUserCleanupService = evaluatedIntegratedWsl.systemd.user.services ? nh-clean;
      hasUserCleanupTimer = evaluatedIntegratedWsl.systemd.user.timers ? nh-clean;
      hasResultRootService = evaluatedIntegratedWsl.systemd.user.services ? nh-clean-result-roots;
      hasResultRootTimer = evaluatedIntegratedWsl.systemd.user.timers ? nh-clean-result-roots;
    };
    expected = {
      clean = expectedDisabledSystemCleanup;
      hasUserCleanupService = false;
      hasUserCleanupTimer = false;
      hasResultRootService = true;
      hasResultRootTimer = true;
    };
  };

  testLinuxFinalResultRootUnits = systemdPlatformTest {
    expr = finalResultRootUnit evaluatedLinux;
    expected = expectedFinalResultRootUnit;
  };

  testWslFinalResultRootUnits = systemdPlatformTest {
    expr = finalResultRootUnit evaluatedWsl;
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
