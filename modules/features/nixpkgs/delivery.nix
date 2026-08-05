{ inputs, ... }:
let
  inherit (import ./_interface) mkOverlayPlan;
  settingsFor = owner: {
    nixpkgs.overlays =
      (mkOverlayPlan {
        inherit inputs;
        system = owner.system;
      }).overlays;
  };
in
{
  features.nixpkgs-host-overlays = {
    name = "feature/nixpkgs/host-overlays";
    nixos = { host, ... }: settingsFor host;
    darwin = { host, ... }: settingsFor host;
  };

  features.nixpkgs-home-overlays = {
    name = "feature/nixpkgs/home-overlays";
    homeManager = { home, ... }: settingsFor home;
  };
}
