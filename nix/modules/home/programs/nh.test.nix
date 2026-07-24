{
  homeManager,
  lib,
  pkgs,
}:
let
  mkModule =
    {
      isLinux ? false,
      isWsl ? false,
    }:
    import ./nh.nix {
      config = {
        home.profileDirectory = "/home/test/.nix-profile";
        my = {
          inherit isLinux isWsl;
        };
        programs.nh.package = "/nix/store/test-nh";
      };
      inherit lib pkgs;
    };

  mkEvaluatedConfig =
    {
      isLinux ? false,
      isWsl ? false,
    }:
    (homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
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

  linuxModule = mkModule { isLinux = true; };
  wslModule = mkModule { isWsl = true; };
  darwinModule = mkModule { };
  evaluatedLinux = mkEvaluatedConfig { isLinux = true; };
  evaluatedWsl = mkEvaluatedConfig { isWsl = true; };
  resultRootPruner = pkgs.callPackage ../../../packages/nh-result-root-pruner { };
  expectedCleanup = {
    enable = true;
    dates = "*-*-* 00/6:00:00";
    extraArgs = "--keep 5 --keep-since 1d --no-gcroots --no-direnv";
  };
  expectedServicePath = [
    "PATH=/home/test/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  ];
  expectedResultRootService = {
    Unit.Description = "Prune stale Nix build result roots";
    Service = {
      Type = "oneshot";
      ExecStart = "${resultRootPruner}/bin/nh-prune-result-roots --keep-minutes 10080";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  expectedResultRootTimer = {
    Unit.Description = "Weekly cleanup of stale Nix build result roots";
    Timer = {
      OnCalendar = "Sun *-*-* 03:00:00";
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
  expectedFinalRegularService = evaluated: {
    Environment = expectedServicePath;
    ExecStart = [ "${evaluated.programs.nh.package}/bin/nh clean user ${expectedCleanup.extraArgs}" ];
    IOSchedulingClass = "idle";
    Nice = 10;
  };
  expectedFinalRegularTimer = {
    OnCalendar = expectedCleanup.dates;
    Persistent = true;
    WantedBy = [ "timers.target" ];
  };
  expectedFinalResultRootUnit = evaluated: {
    service = expectedResultRootService // {
      Service = expectedResultRootService.Service // {
        ExecStart = [ "${resultRootPruner}/bin/nh-prune-result-roots --keep-minutes 10080" ];
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
  testCleanupPolicyLimitsHighChurnProfiles = {
    expr = linuxModule.programs.nh.clean;
    expected = expectedCleanup;
  };

  testWslUsesCleanupPolicy = {
    expr = wslModule.programs.nh.clean;
    expected = expectedCleanup;
  };

  testLinuxCleanupCanResolveNix = {
    expr = linuxModule.systemd.user.services.nh-clean.Service;
    expected = {
      Environment = expectedServicePath;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  testWslCleanupCanResolveNix = {
    expr = wslModule.systemd.user.services.nh-clean.Service;
    expected = {
      Environment = expectedServicePath;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  testLinuxPrunesOnlyStaleResultRoots = {
    expr = linuxModule.systemd.user.services.nh-clean-result-roots;
    expected = expectedResultRootService;
  };

  testWslPrunesOnlyStaleResultRoots = {
    expr = wslModule.systemd.user.services.nh-clean-result-roots;
    expected = expectedResultRootService;
  };

  testLinuxSchedulesResultRootCleanup = {
    expr = linuxModule.systemd.user.timers.nh-clean-result-roots;
    expected = expectedResultRootTimer;
  };

  testWslSchedulesResultRootCleanup = {
    expr = wslModule.systemd.user.timers.nh-clean-result-roots;
    expected = expectedResultRootTimer;
  };

  testLinuxFinalCleanupService = systemdPlatformTest {
    expr = finalRegularService evaluatedLinux;
    expected = expectedFinalRegularService evaluatedLinux;
  };

  testWslFinalCleanupService = systemdPlatformTest {
    expr = finalRegularService evaluatedWsl;
    expected = expectedFinalRegularService evaluatedWsl;
  };

  testLinuxFinalCleanupTimer = systemdPlatformTest {
    expr = finalRegularTimer evaluatedLinux;
    expected = expectedFinalRegularTimer;
  };

  testWslFinalCleanupTimer = systemdPlatformTest {
    expr = finalRegularTimer evaluatedWsl;
    expected = expectedFinalRegularTimer;
  };

  testLinuxFinalResultRootUnits = systemdPlatformTest {
    expr = finalResultRootUnit evaluatedLinux;
    expected = expectedFinalResultRootUnit evaluatedLinux;
  };

  testWslFinalResultRootUnits = systemdPlatformTest {
    expr = finalResultRootUnit evaluatedWsl;
    expected = expectedFinalResultRootUnit evaluatedWsl;
  };

  testDarwinDoesNotDefineSystemdCleanup = {
    expr = {
      inherit (darwinModule.systemd.user) services timers;
    };
    expected = {
      services = { };
      timers = { };
    };
  };

  testDarwinDisablesCleanup = {
    expr = darwinModule.programs.nh.clean;
    expected = {
      enable = false;
      dates = "weekly";
      extraArgs = "--keep 5 --keep-since 1d --no-gcroots --no-direnv";
    };
  };
}
