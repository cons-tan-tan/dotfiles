{
  den,
  features,
  inputs,
  ...
}:
let
  profileAssertion = import ./_lib/profile-assertion.nix;
  inherit (import ../../features/nixpkgs/_interface) mkOverlayPlan;
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
        overlayPlan = mkOverlayPlan {
          inherit inputs;
          system = home.system;
        };
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
        };
        nixpkgs = {
          overlays = overlayPlan.overlays;
        };
      };
  };
}
