{
  lib,
  pkgs,
  username,
}:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  daemonModule =
    if isDarwin then
      import ./sleepctl-daemon.nix {
        inherit pkgs username;
      }
    else
      null;
  service = if isDarwin then daemonModule.launchd.daemons.sleepctld.serviceConfig else null;
  systemModule = import ./system.nix {
    config = { };
    inherit lib pkgs username;
    homedir = "/Users/${username}";
  };
in
{
  testSleepctlPackageMatchesPlatform = {
    expr = pkgs.dotfilesPackages ? sleepctl;
    expected = isDarwin;
  };

  testSystemImportsSleepctlDaemon = {
    expr = builtins.elem ./sleepctl-daemon.nix systemModule.imports;
    expected = true;
  };
}
// lib.optionalAttrs isDarwin {
  testSleepctlDaemonUsesFixedProgram = {
    expr = service.ProgramArguments;
    expected = [
      "${pkgs.dotfilesPackages.sleepctl}/bin/sleepctld"
      "--allowed-user"
      username
    ];
  };

  testSleepctlDaemonLifecycleIsFixed = {
    expr = {
      inherit (service)
        KeepAlive
        ProcessType
        RunAtLoad
        ThrottleInterval
        ;
    };
    expected = {
      KeepAlive = true;
      ProcessType = "Background";
      RunAtLoad = true;
      ThrottleInterval = 5;
    };
  };

  testSleepctlDaemonDoesNotOverrideUser = {
    expr = service ? UserName;
    expected = false;
  };
}
