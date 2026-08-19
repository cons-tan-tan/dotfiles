{
  darwin,
  darwinResult,
  darwinSystem,
  lib,
  username,
}:
let
  homebrewCasks = map (
    cask: if builtins.isString cask then cask else cask.name
  ) darwinSystem.homebrew.casks;
in
{
  actual = {
    inherit (darwinSystem.system) primaryUser stateVersion;
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
    ghostty = darwin.programs.ghostty.enable;
    homebrew = darwinSystem.homebrew.enable;
    requiredHomebrewCasks = lib.all (cask: builtins.elem cask homebrewCasks) [
      "azookey"
      "fiji"
      "scroll-reverser"
      "tailscale-app"
    ];
    fonts = {
      hackgen = builtins.elem darwinResult.pkgs.hackgen-nf-font darwinSystem.fonts.packages;
      symbols = builtins.elem darwinResult.pkgs.nerd-fonts.symbols-only darwinSystem.fonts.packages;
    };
    touchId = darwinSystem.security.pam.services.sudo_local.touchIdAuth;
  };
  expected = {
    primaryUser = username;
    stateVersion = 5;
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
    ghostty = true;
    homebrew = true;
    requiredHomebrewCasks = true;
    fonts = {
      hackgen = true;
      symbols = true;
    };
    touchId = true;
  };
}
