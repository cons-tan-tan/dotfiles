{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  isSystemdHost = config.my.isLinux || config.my.isWsl;
  isNixosIntegrated = osConfig != null;
  # Standalone WSL installs the cleanup policy as system units from the host
  # switch app, so it does not depend on the user manager or WSLg mount order.
  enableUserCleanup = isSystemdHost && !config.my.isWsl && !isNixosIntegrated;
  enableUserResultRootCleanup = isSystemdHost && !config.my.isWsl;
  cleanupPolicy = import ../../../lib/nh-clean-policy.nix;
  cleanupArgs = lib.escapeShellArgs cleanupPolicy.arguments;
  nixPackage =
    if config.nix.enable && config.nix.package != null then config.nix.package else pkgs.nix;
  userCleanupRunner = pkgs.callPackage ../../../packages/nh-clean-user {
    nh = config.programs.nh.package;
    nix = nixPackage;
  };
  resultRootPruner = pkgs.callPackage ../../../packages/nh-result-root-pruner { };
in
{
  programs.nh = {
    enable = true;

    clean = {
      # Home Manager currently appends extraArgs as one launchd argument.
      # NixOS also needs root access to prune its system generations, so its
      # system module owns cleanup instead of this user-scoped service.
      enable = enableUserCleanup;
      dates = if isSystemdHost then cleanupPolicy.dates else "weekly";
      extraArgs = cleanupArgs;
    };
  };

  systemd.user.services =
    lib.optionalAttrs enableUserResultRootCleanup {
      # The multi-user Nix daemon owns the auto-root registry, so a user service
      # expires the user's result symlinks and lets the next Nix GC drop the
      # resulting stale registrations.
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
}
