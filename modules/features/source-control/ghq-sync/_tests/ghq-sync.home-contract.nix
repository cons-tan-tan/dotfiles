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
    in
    {
      package = countPackage pkgs.ghq;
      systemd = systemdServices ? ghq-fetch && systemdTimers ? ghq-fetch;
      launchd = launchdAgents ? ghq-fetch;
      schedule =
        if launchdAgents ? ghq-fetch then
          launchdAgents.ghq-fetch.config.StartInterval == 600
          && lib.any (
            command: lib.hasInfix "ghq-fetch-all" command
          ) launchdAgents.ghq-fetch.config.ProgramArguments
        else
          systemdTimers.ghq-fetch.Timer.OnUnitActiveSec == "10min"
          && systemdServices.ghq-fetch.Service.TimeoutStartSec == 600
          && systemdServices.ghq-fetch.Service.Type == "oneshot"
          && lib.any (
            command: lib.hasInfix "ghq-fetch-all" command
          ) systemdServices.ghq-fetch.Service.ExecStart;
      durability =
        if launchdAgents ? ghq-fetch then
          launchdAgents.ghq-fetch.config.Nice == 10
          && launchdAgents.ghq-fetch.config.ProcessType == "Background"
        else
          systemdTimers.ghq-fetch.Timer.Persistent
          && systemdTimers.ghq-fetch.Timer.OnBootSec == "2min"
          && systemdTimers.ghq-fetch.Timer.RandomizedDelaySec == "30s"
          && builtins.elem "network-online.target" systemdServices.ghq-fetch.Unit.After
          && builtins.elem "network-online.target" systemdServices.ghq-fetch.Unit.Wants
          && systemdServices.ghq-fetch.Service.Nice == 10
          && systemdServices.ghq-fetch.Service.IOSchedulingClass == "idle";
    };
  expected = facts: {
    package = 1;
    systemd = facts.environment != "darwin";
    launchd = facts.environment == "darwin";
    schedule = true;
    durability = true;
  };
}
