{
  lib,
}:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      systemdServices = lib.attrByPath [ "systemd" "user" "services" ] { } config;
      systemdTimers = lib.attrByPath [ "systemd" "user" "timers" ] { } config;
      launchdAgents = lib.attrByPath [ "launchd" "agents" ] { } config;
      countPackage =
        package: builtins.length (builtins.filter (candidate: candidate == package) config.home.packages);
      providers = {
        launchd = launchdAgents ? ghq-fetch;
        systemd = systemdServices ? ghq-fetch && systemdTimers ? ghq-fetch;
      };
      service =
        (
          if providers.launchd then
            {
              backend = "launchd";
              schedule = {
                interval = launchdAgents.ghq-fetch.config.StartInterval;
                invokesFetchAll = lib.any (
                  command: lib.hasInfix "ghq-fetch-all" command
                ) launchdAgents.ghq-fetch.config.ProgramArguments;
              };
              durability = {
                nice = launchdAgents.ghq-fetch.config.Nice;
                processType = launchdAgents.ghq-fetch.config.ProcessType;
              };
            }
          else if providers.systemd then
            {
              backend = "systemd";
              schedule = {
                interval = systemdTimers.ghq-fetch.Timer.OnUnitActiveSec;
                timeout = systemdServices.ghq-fetch.Service.TimeoutStartSec;
                type = systemdServices.ghq-fetch.Service.Type;
                invokesFetchAll = lib.any (
                  command: lib.hasInfix "ghq-fetch-all" command
                ) systemdServices.ghq-fetch.Service.ExecStart;
              };
              durability = {
                persistent = systemdTimers.ghq-fetch.Timer.Persistent;
                bootDelay = systemdTimers.ghq-fetch.Timer.OnBootSec;
                randomizedDelay = systemdTimers.ghq-fetch.Timer.RandomizedDelaySec;
                afterNetworkOnline = builtins.elem "network-online.target" systemdServices.ghq-fetch.Unit.After;
                wantsNetworkOnline = builtins.elem "network-online.target" systemdServices.ghq-fetch.Unit.Wants;
                nice = systemdServices.ghq-fetch.Service.Nice;
                ioSchedulingClass = systemdServices.ghq-fetch.Service.IOSchedulingClass;
              };
            }
          else
            { backend = "missing"; }
        )
        // {
          inherit providers;
        };
    in
    {
      package = countPackage pkgs.ghq;
      inherit service;
    };
  expected = facts: {
    package = 1;
    service =
      if facts.environment == "darwin" then
        {
          backend = "launchd";
          providers = {
            launchd = true;
            systemd = false;
          };
          schedule = {
            interval = 600;
            invokesFetchAll = true;
          };
          durability = {
            nice = 10;
            processType = "Background";
          };
        }
      else
        {
          backend = "systemd";
          providers = {
            launchd = false;
            systemd = true;
          };
          schedule = {
            interval = "10min";
            timeout = 600;
            type = "oneshot";
            invokesFetchAll = true;
          };
          durability = {
            persistent = true;
            bootDelay = "2min";
            randomizedDelay = "30s";
            afterNetworkOnline = true;
            wantsNetworkOnline = true;
            nice = 10;
            ioSchedulingClass = "idle";
          };
        };
  };
}
