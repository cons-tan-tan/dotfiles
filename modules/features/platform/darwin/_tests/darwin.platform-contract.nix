{
  darwinResult,
  darwinSystem,
  username,
}:
{
  actual = {
    sleepctlArguments = darwinSystem.launchd.daemons.sleepctld.serviceConfig.ProgramArguments;
    sleepctlLifecycle = {
      inherit (darwinSystem.launchd.daemons.sleepctld.serviceConfig)
        KeepAlive
        ProcessType
        RunAtLoad
        ThrottleInterval
        ;
      userName = darwinSystem.launchd.daemons.sleepctld.serviceConfig.UserName or null;
    };
  };
  expected = {
    sleepctlArguments = [
      "${darwinResult.pkgs.dotfilesPackages.sleepctl}/bin/sleepctld"
      "--allowed-user"
      username
    ];
    sleepctlLifecycle = {
      KeepAlive = true;
      ProcessType = "Background";
      RunAtLoad = true;
      ThrottleInterval = 5;
      userName = null;
    };
  };
}
