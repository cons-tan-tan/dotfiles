{ config, ... }:
let
  intervalMin = 10;
  batchTimeoutSec = 600;
in
{
  flake.modules.homeManager.ghq-sync = {
    key = "modules/features/git/ghq-sync/default.nix#homeManager.ghq-sync";
    dotfiles.cliTools = [
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

  flake.modules.homeManager.ghq-sync-systemd = {
    key = "modules/features/git/ghq-sync/default.nix#homeManager.ghq-sync-systemd";
    imports = [
      config.flake.modules.homeManager.ghq-sync
      (
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
        }
      )
    ];
  };

  flake.modules.homeManager.ghq-sync-launchd = {
    key = "modules/features/git/ghq-sync/default.nix#homeManager.ghq-sync-launchd";
    imports = [
      config.flake.modules.homeManager.ghq-sync
      (
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
        }
      )
    ];
  };
}
