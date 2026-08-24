{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;
  overlayPlan = (import ../_interface).mkOverlayPlan {
    inherit inputs;
    inherit system;
  };
  watchexecPin = (import ../../development/watchexec/_interface.nix).pin;
in
{
  testOverlayNamesAreUnique = {
    expr = builtins.length (pkgs.lib.unique overlayPlan.names);
    expected = builtins.length overlayPlan.names;
  };

  testOverlayCountMatchesNames = {
    expr = builtins.length overlayPlan.overlays;
    expected = builtins.length overlayPlan.names;
  };

  testDarwinOnlyOverlaysMatchPlatform = {
    expr = {
      brewCasks = pkgs ? brewCasks;
      pinnedWatchexec =
        pkgs.watchexec.version == watchexecPin.version
        && builtins.elem pkgs.lib.sourceTypes.binaryNativeCode (
          pkgs.watchexec.meta.sourceProvenance or [ ]
        );
    };
    expected = {
      brewCasks = pkgs.stdenv.hostPlatform.isDarwin;
      pinnedWatchexec = pkgs.stdenv.hostPlatform.isDarwin;
    };
  };

}
