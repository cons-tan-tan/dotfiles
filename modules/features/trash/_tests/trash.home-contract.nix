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
      providers = {
        launchd = launchdAgents ? trash-gc;
        systemd = systemdServices ? trash-gc && systemdTimers ? trash-gc;
      };
      service =
        (
          if providers.launchd then
            let
              calendar = builtins.head launchdAgents.trash-gc.config.StartCalendarInterval;
            in
            {
              backend = "launchd";
              schedule = {
                hour = calendar.Hour;
                minute = calendar.Minute;
              };
              durability = {
                domain = launchdAgents.trash-gc.domain;
                nice = launchdAgents.trash-gc.config.Nice;
                processType = launchdAgents.trash-gc.config.ProcessType;
              };
            }
          else if providers.systemd then
            {
              backend = "systemd";
              schedule.calendar = systemdTimers.trash-gc.Timer.OnCalendar;
              durability = {
                persistent = systemdTimers.trash-gc.Timer.Persistent;
                randomizedDelay = systemdTimers.trash-gc.Timer.RandomizedDelaySec;
                ioSchedulingClass = systemdServices.trash-gc.Service.IOSchedulingClass;
                nice = systemdServices.trash-gc.Service.Nice;
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
      activation = {
        inherit (activation) after;
        usesRun = lib.hasPrefix "run " activation.data;
        createsFilesDirectory = lib.hasInfix "Trash/files" activation.data;
        createsInfoDirectory = lib.hasInfix "Trash/info" activation.data;
        restrictsPermissions = lib.hasInfix "chmod 0700" activation.data;
      };
      package = builtins.elem pkgs.trash-cli config.home.packages;
      inherit service;
    };
  expected = facts: {
    activation = {
      after = [ "writeBoundary" ];
      usesRun = true;
      createsFilesDirectory = true;
      createsInfoDirectory = true;
      restrictsPermissions = true;
    };
    package = true;
    service =
      if facts.environment == "darwin" then
        {
          backend = "launchd";
          providers = {
            launchd = true;
            systemd = false;
          };
          schedule = {
            hour = 3;
            minute = 0;
          };
          durability = {
            domain = "user";
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
          schedule.calendar = "*-*-* 03:00:00";
          durability = {
            persistent = true;
            randomizedDelay = "30min";
            ioSchedulingClass = "idle";
            nice = 10;
          };
        };
  };
}
