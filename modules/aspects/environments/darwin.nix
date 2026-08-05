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
        overlayPlan = mkOverlayPlan {
          inherit inputs;
          system = host.system;
        };
      in
      {
        assertions = [
          (profileAssertion {
            expected = "darwin";
            owner = host;
          })
        ];
        nixpkgs = {
          overlays = overlayPlan.overlays;
        };
      };

    homeManager =
      { host, ... }:
      {
        assertions = [
          (profileAssertion {
            expected = "darwin";
            owner = host;
          })
        ];
        dotfiles.platform = {
          inherit (host.dotfiles) environment source;
          standalone = false;
        };
      };
  };
}
