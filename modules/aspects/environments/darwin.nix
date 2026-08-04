{
  den,
  features,
  inputs,
  ...
}:
{
  den.aspects.environments.darwin = {
    name = "dotfiles-darwin";
    includes = [
      den.aspects.environments.base
      den.aspects.environments.integrated-home-manager
      features.registries-host
      features.security-gpg-darwin
      features.source-control-ghq-sync-launchd
      features.trash-darwin
      features.platform-darwin
    ];

    darwin =
      { host, ... }:
      let
        overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } host.system;
      in
      {
        nixpkgs = {
          overlays = overlayPlan.overlays;
        };
      };

    homeManager =
      { host, ... }:
      {
        dotfiles.platform = {
          inherit (host.dotfiles) environment source;
          standalone = false;
          windowsCompanion = false;
          nhCleanupOwner = "none";
        };
        dotfiles.agentEnvironment = {
          inherit (host.dotfiles) environment source;
        };
      };
  };
}
