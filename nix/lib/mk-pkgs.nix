{
  inputs,
  extraOverlays ? [ ],
  unfreePackageNames ? [ ],
}:
system:
let
  overlayPlan = import ./mk-overlays.nix { inherit inputs; } system;
in
import inputs.nixpkgs {
  inherit system;
  config.allowUnfreePredicate =
    package: builtins.elem (inputs.nixpkgs.lib.getName package) unfreePackageNames;
  overlays = overlayPlan.overlays ++ extraOverlays;
}
