{
  darwin,
  darwinResult,
  darwinSystem,
  lib,
  username,
}:
let
  fontsContribution = (import ../fonts.nix { }).features.platform-darwin-fonts.darwin {
    pkgs = darwinResult.pkgs;
  };
  touchIdFeature = (import ../touch-id.nix { }).features.platform-darwin-touch-id;
  touchIdContribution = touchIdFeature.darwin;
  featureNames = [
    "platform-context"
    "platform-darwin-system"
    "platform-darwin-fonts"
    "platform-darwin-touch-id"
    "platform-homebrew"
    "input-methods-azookey"
    "media-aqua-voice"
    "media-fiji"
    "network-tailscale"
    "platform-darwin-scroll-reverser"
    "productivity-raycast"
    "platform-ghostty"
    "platform-sleepctl"
    "platform-nh"
  ];
  featureMarkers = lib.genAttrs featureNames (name: name);
  aggregate =
    (import ../default.nix {
      features = featureMarkers;
    }).features.platform-darwin;
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
    homebrewCasks = lib.sort builtins.lessThan (
      map (cask: if builtins.isString cask then cask else cask.name) darwinSystem.homebrew.casks
    );
    independentFeatures = {
      aggregate = {
        hackgen = lib.elem darwinResult.pkgs.hackgen-nf-font darwinSystem.fonts.packages;
        symbols = lib.elem darwinResult.pkgs.nerd-fonts.symbols-only darwinSystem.fonts.packages;
        touchId = darwinSystem.security.pam.services.sudo_local.touchIdAuth;
      };
      fontsOnly = {
        hackgen = lib.elem darwinResult.pkgs.hackgen-nf-font fontsContribution.fonts.packages;
        symbols = lib.elem darwinResult.pkgs.nerd-fonts.symbols-only fontsContribution.fonts.packages;
        ownsTouchId = fontsContribution ? security;
      };
      touchIdOnly = {
        enabled = touchIdContribution.security.pam.services.sudo_local.touchIdAuth;
        name = touchIdFeature.name;
      };
    };
    aggregate = {
      attributes = builtins.attrNames aggregate;
      includes = aggregate.includes;
      name = aggregate.name;
    };
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
    homebrewCasks = [
      "azookey"
      "fiji"
      "scroll-reverser"
      "tailscale-app"
    ];
    independentFeatures = {
      aggregate = {
        hackgen = true;
        symbols = true;
        touchId = true;
      };
      fontsOnly = {
        hackgen = true;
        symbols = true;
        ownsTouchId = false;
      };
      touchIdOnly = {
        enabled = true;
        name = "feature/platform/darwin/touch-id";
      };
    };
    aggregate = {
      attributes = [
        "includes"
        "name"
      ];
      includes = featureNames;
      name = "feature/platform/darwin";
    };
  };
}
