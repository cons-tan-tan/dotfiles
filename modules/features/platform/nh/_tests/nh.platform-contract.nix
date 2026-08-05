{
  lib,
  standaloneLinux,
  standaloneLinuxResult,
  standaloneWsl,
  integratedWsl,
  integratedWslSystem,
  darwin,
  darwinSystem,
}:
let
  cleanupPolicy = import ../_lib/cleanup-policy.nix;
  cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;
  linuxCleanupRunner = standaloneLinuxResult.pkgs.callPackage ../_packages/clean-user {
    nh = standaloneLinux.programs.nh.package;
    nix = standaloneLinuxResult.pkgs.nix;
  };
  linuxResultRootPruner = standaloneLinuxResult.pkgs.callPackage ../_packages/result-root-pruner { };
in
{
  actual = {
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
  expected = {
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
}
