{
  lib,
}:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      activation = config.home.activation.trashDirectory;
      trashDirectory = "${config.xdg.dataHome}/Trash";
      systemdServices = lib.attrByPath [ "systemd" "user" "services" ] { } config;
      systemdTimers = lib.attrByPath [ "systemd" "user" "timers" ] { } config;
      launchdAgents = lib.attrByPath [ "launchd" "agents" ] { } config;
      providers = {
        launchd = launchdAgents ? trash-gc;
        systemd = systemdServices ? trash-gc && systemdTimers ? trash-gc;
      };
    in
    {
      activation = {
        inherit (activation) after;
        executable = lib.hasInfix "/bin/prepare-trash-directory" activation.data;
        directory = lib.hasInfix "TRASH_DIRECTORY=${lib.escapeShellArg trashDirectory}" activation.data;
      };
      package = builtins.elem pkgs.trash-cli config.home.packages;
      inherit providers;
    };
  expected = facts: {
    activation = {
      after = [ "writeBoundary" ];
      executable = true;
      directory = true;
    };
    package = true;
    providers =
      if facts.environment == "darwin" then
        {
          launchd = true;
          systemd = false;
        }
      else
        {
          launchd = false;
          systemd = true;
        };
  };
}
