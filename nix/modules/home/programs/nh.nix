{
  config,
  lib,
  pkgs,
  ...
}:
let
  isSystemdHost = config.my.isLinux || config.my.isWsl;
  servicePath = "${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
  resultRootPruner = pkgs.callPackage ../../../packages/nh-result-root-pruner { };
in
{
  programs.nh = {
    enable = true;

    clean = {
      # Home Manager currently appends extraArgs as one launchd argument.
      # Keep automatic cleanup on the systemd-backed hosts where it is split correctly.
      enable = isSystemdHost;
      dates = if isSystemdHost then "*-*-* 00/6:00:00" else "weekly";
      extraArgs = "--keep 5 --keep-since 1d --no-gcroots --no-direnv";
    };
  };

  # nh resolves nix as a child process, while the user manager does not inherit
  # the Nix paths configured by the interactive shell.
  systemd.user.services = lib.optionalAttrs isSystemdHost {
    nh-clean.Service = {
      Environment = [ "PATH=${servicePath}" ];
      Nice = 10;
      IOSchedulingClass = "idle";
    };

    # The multi-user Nix daemon owns the auto-root registry, so a user service
    # expires the user's result symlinks and lets the next Nix GC drop the
    # resulting stale registrations.
    nh-clean-result-roots = {
      Unit.Description = "Prune stale Nix build result roots";
      Service = {
        Type = "oneshot";
        ExecStart = "${resultRootPruner}/bin/nh-prune-result-roots --keep-minutes 10080";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };
  };

  systemd.user.timers = lib.optionalAttrs isSystemdHost {
    nh-clean-result-roots = {
      Unit.Description = "Weekly cleanup of stale Nix build result roots";
      Timer = {
        OnCalendar = "Sun *-*-* 03:00:00";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
