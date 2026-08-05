{
  lib,
}:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      activation = config.home.activation.trashDirectory;
      systemdServices = lib.attrByPath [ "systemd" "user" "services" ] { } config;
      systemdTimers = lib.attrByPath [ "systemd" "user" "timers" ] { } config;
      launchdAgents = lib.attrByPath [ "launchd" "agents" ] { } config;
    in
    {
      activation = {
        afterWriteBoundary = activation.after == [ "writeBoundary" ];
        usesRun = lib.hasPrefix "run " activation.data;
        createsFreedesktopDirectories =
          lib.hasInfix "Trash/files" activation.data && lib.hasInfix "Trash/info" activation.data;
        restrictsPermissions = lib.hasInfix "chmod 0700" activation.data;
      };
      package = builtins.elem pkgs.trash-cli config.home.packages;
      service = {
        systemd = systemdServices ? trash-gc && systemdTimers ? trash-gc;
        launchd = launchdAgents ? trash-gc;
        schedule =
          if launchdAgents ? trash-gc then
            let
              calendar = builtins.head launchdAgents.trash-gc.config.StartCalendarInterval;
            in
            calendar.Hour == 3 && calendar.Minute == 0
          else
            systemdTimers.trash-gc.Timer.OnCalendar == "*-*-* 03:00:00";
        durability =
          if launchdAgents ? trash-gc then
            launchdAgents.trash-gc.domain == "user"
            && launchdAgents.trash-gc.config.Nice == 10
            && launchdAgents.trash-gc.config.ProcessType == "Background"
          else
            systemdTimers.trash-gc.Timer.Persistent
            && systemdTimers.trash-gc.Timer.RandomizedDelaySec == "30min"
            && systemdServices.trash-gc.Service.Nice == 10
            && systemdServices.trash-gc.Service.IOSchedulingClass == "idle";
      };
    };
  expected = facts: {
    activation = {
      afterWriteBoundary = true;
      usesRun = true;
      createsFreedesktopDirectories = true;
      restrictsPermissions = true;
    };
    package = true;
    service = {
      systemd = facts.environment != "darwin";
      launchd = facts.environment == "darwin";
      schedule = true;
      durability = true;
    };
  };
}
