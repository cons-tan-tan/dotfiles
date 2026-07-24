{ pkgs, username, ... }:
{
  launchd.daemons.sleepctld.serviceConfig = {
    ProgramArguments = [
      "${pkgs.dotfilesPackages.sleepctl}/bin/sleepctld"
      "--allowed-user"
      username
    ];
    RunAtLoad = true;
    KeepAlive = true;
    ProcessType = "Background";
    ThrottleInterval = 5;
    StandardOutPath = "/var/log/sleepctld.log";
    StandardErrorPath = "/var/log/sleepctld.err.log";
  };
}
