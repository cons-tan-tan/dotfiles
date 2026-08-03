{ inputs }:
system:
let
  overlayPlan = import ./mk-overlays.nix { inherit inputs; } system;
in
import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
  inherit (overlayPlan) overlays;
}
