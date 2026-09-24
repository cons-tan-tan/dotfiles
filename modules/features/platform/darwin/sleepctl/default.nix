_: {
  flake.modules.darwin.platform-sleepctl =
    { config, pkgs, ... }:
    {
      key = "modules/features/platform/darwin/sleepctl/default.nix#darwin.platform-sleepctl";

      launchd.daemons.sleepctld.serviceConfig = {
        ProgramArguments = [
          "${pkgs.dotfilesPackages.sleepctl}/bin/sleepctld"
          "--allowed-user"
          config.system.primaryUser
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        ThrottleInterval = 5;
        StandardOutPath = "/var/log/sleepctld.log";
        StandardErrorPath = "/var/log/sleepctld.err.log";
      };
    };

  flake.modules.homeManager.platform-sleepctl = { pkgs, ... }: {
    key = "modules/features/platform/darwin/sleepctl/default.nix#homeManager.platform-sleepctl";

    home.packages = [ pkgs.dotfilesPackages.sleepctl ];
  };
}
