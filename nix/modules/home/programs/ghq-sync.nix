{
  config,
  pkgs,
  lib,
  ...
}:
let
  intervalMin = 10;
  maxJobs = 8;
  perRepoTimeoutSec = 60;
  batchTimeoutSec = 600;

  fetchScript = pkgs.writeShellApplication {
    name = "ghq-fetch-all";
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    runtimeInputs = with pkgs; [
      ghq
      git
      coreutils
      findutils
    ];
    # The `sh -c '...'` body intentionally defers `$1` expansion to the child
    # shell spawned by xargs, so SC2016 is a false positive here.
    excludeShellChecks = [ "SC2016" ];
    text = ''
      ghq list -p \
        | xargs -P${toString maxJobs} -I{} sh -c '
            if ! timeout ${toString perRepoTimeoutSec}s \
                  git -C "$1" fetch --all --prune --quiet 2>&1; then
              echo "WARN: fetch failed for $1" >&2
            fi
          ' _ {}
    '';
  };

in
lib.mkMerge [
  (lib.mkIf (config.my.isLinux || config.my.isWsl) {
    systemd.user.services.ghq-fetch = {
      Unit = {
        Description = "Fetch all ghq-managed git repositories";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${fetchScript}/bin/ghq-fetch-all";
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = batchTimeoutSec;
      };
    };

    systemd.user.timers.ghq-fetch = {
      Unit.Description = "Periodic ghq fetch";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString intervalMin}min";
        RandomizedDelaySec = "30s";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  })

  (lib.mkIf config.my.isDarwin {
    launchd.agents.ghq-fetch = {
      enable = true;
      config = {
        ProgramArguments = [ "${fetchScript}/bin/ghq-fetch-all" ];
        StartInterval = intervalMin * 60;
        Nice = 10;
        ProcessType = "Background";
        StandardOutPath = "/tmp/ghq-fetch.out.log";
        StandardErrorPath = "/tmp/ghq-fetch.err.log";
      };
    };
  })
]
