{
  den,
  features,
  inputs,
  ...
}:
let
  profileAssertion = import ./_lib/profile-assertion.nix;
in
{
  den.aspects.environments.linux = {
    name = "dotfiles-linux";
    includes = [
      den.aspects.environments.base
      features.registries-home
      features.security-gpg-linux
      features.source-control-ghq-sync-systemd
      features.trash-systemd
      features.platform-linux
    ];

    homeManager =
      { home, ... }:
      let
        overlayPlan = import ../../../nix/lib/mk-overlays.nix { inherit inputs; } home.system;
      in
      {
        assertions = [
          (profileAssertion {
            expected = "linux";
            owner = home;
          })
        ];
        dotfiles.platform = {
          inherit (home.dotfiles) environment source standalone;
          windowsCompanion = false;
          nhCleanupOwner = "home-manager";
        };
        dotfiles.agentEnvironment = {
          inherit (home.dotfiles) environment source;
        };
        nixpkgs = {
          overlays = overlayPlan.overlays;
        };
      };
  };
}
