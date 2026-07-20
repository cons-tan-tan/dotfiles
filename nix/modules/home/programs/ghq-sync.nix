{
  config,
  pkgs,
  lib,
  ...
}:
let
  intervalMin = 10;
  batchTimeoutSec = 600;

  fetchScript = pkgs.dotfilesPackages.ghq-fetch-all;
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
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ghq-fetch.out.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ghq-fetch.err.log";
      };
    };
  })
]
