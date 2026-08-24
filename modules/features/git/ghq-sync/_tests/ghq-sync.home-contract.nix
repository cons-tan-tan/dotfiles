{ lib }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      fetchAll = "${pkgs.dotfilesPackages.ghq-fetch-all}/bin/ghq-fetch-all";
      systemdServices = lib.attrByPath [ "systemd" "user" "services" ] { } config;
      systemdTimers = lib.attrByPath [ "systemd" "user" "timers" ] { } config;
      launchdAgents = lib.attrByPath [ "launchd" "agents" ] { } config;
      providers = {
        launchd = launchdAgents ? ghq-fetch;
        systemd = systemdServices ? ghq-fetch && systemdTimers ? ghq-fetch;
      };
    in
    if providers.launchd then
      {
        backend = "launchd";
        invokesFetchAll = launchdAgents.ghq-fetch.config.ProgramArguments == [ fetchAll ];
        inherit providers;
      }
    else if providers.systemd then
      {
        backend = "systemd";
        invokesFetchAll = systemdServices.ghq-fetch.Service.ExecStart == [ fetchAll ];
        inherit providers;
      }
    else
      {
        backend = "missing";
        invokesFetchAll = false;
        inherit providers;
      };
  expected = facts: {
    backend = if facts.environment == "darwin" then "launchd" else "systemd";
    invokesFetchAll = true;
    providers = {
      launchd = facts.environment == "darwin";
      systemd = facts.environment != "darwin";
    };
  };
}
