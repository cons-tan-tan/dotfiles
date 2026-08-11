{
  lib,
  linux,
  pkgs,
  wsl,
}:
let
  cleanupPolicy = import ../_data/cleanup-policy.nix;
  cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;
  linuxCleanupRunner = linux.pkgs.callPackage ../_packages/clean-user {
    nh = linux.config.programs.nh.package;
    nix = linux.pkgs.nix;
  };
  linuxResultRootPruner = linux.pkgs.callPackage ../_packages/result-root-pruner { };
  contracts = {
    standaloneLinux = {
      actual = {
        clean = linux.config.programs.nh.clean;
        service = {
          inherit (linux.config.systemd.user.services.nh-clean.Service)
            Environment
            ExecStart
            IOSchedulingClass
            Nice
            ;
        };
        timer = {
          inherit (linux.config.systemd.user.timers.nh-clean.Install) WantedBy;
          inherit (linux.config.systemd.user.timers.nh-clean.Timer) OnCalendar Persistent;
        };
        resultRoots = {
          service = {
            Unit.Description = linux.config.systemd.user.services.nh-clean-result-roots.Unit.Description;
            Service = {
              inherit (linux.config.systemd.user.services.nh-clean-result-roots.Service)
                ExecStart
                IOSchedulingClass
                Nice
                Type
                ;
            };
          };
          timer = {
            Unit.Description = linux.config.systemd.user.timers.nh-clean-result-roots.Unit.Description;
            inherit (linux.config.systemd.user.timers.nh-clean-result-roots) Install Timer;
          };
        };
      };
      expected = {
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
    };
    standaloneWsl = {
      actual = {
        clean = wsl.config.programs.nh.clean.enable;
        service = wsl.config.systemd.user.services ? nh-clean;
        timer = wsl.config.systemd.user.timers ? nh-clean;
        resultRootService = wsl.config.systemd.user.services ? nh-clean-result-roots;
        resultRootTimer = wsl.config.systemd.user.timers ? nh-clean-result-roots;
      };
      expected = {
        clean = false;
        service = false;
        timer = false;
        resultRootService = false;
        resultRootTimer = false;
      };
    };
  };
  failures = lib.filterAttrs (_: contract: contract.actual != contract.expected) contracts;
in
assert lib.assertMsg (failures == { }) ''
  Home Manager NH cleanup contract mismatches:
  ${builtins.toJSON failures}
'';
pkgs.runCommand "home-nh-cleanup-contract" { } ''touch "$out"''
