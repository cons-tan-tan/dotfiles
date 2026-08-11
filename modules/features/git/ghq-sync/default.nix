{ features, ... }:
let
  intervalMin = 10;
  batchTimeoutSec = 600;
in
{
  features.ghq-sync = {
    name = "feature/ghq-sync";
    cli-tools = [
      {
        id = "ghq";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "ghq";
        };
        winget = {
          packageId = "x-motemen.ghq";
          dependsOn = [ "git" ];
          description = "ghq";
        };
      }
    ];
  };

  features.ghq-sync-systemd = {
    name = "feature/ghq-sync/systemd";
    includes = [ features.ghq-sync ];
    homeManager =
      { pkgs, ... }:
      let
        fetchScript = pkgs.dotfilesPackages.ghq-fetch-all;
      in
      {
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
      };
  };

  features.ghq-sync-launchd = {
    name = "feature/ghq-sync/launchd";
    includes = [ features.ghq-sync ];
    homeManager =
      { config, pkgs, ... }:
      let
        fetchScript = pkgs.dotfilesPackages.ghq-fetch-all;
      in
      {
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
      };
  };
}
