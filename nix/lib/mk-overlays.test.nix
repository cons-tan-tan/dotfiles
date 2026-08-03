{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;
  overlayPlan = import ./mk-overlays.nix { inherit inputs; } system;
  commonNames = [
    "mozuku-lsp"
    "llm-agents"
    "local-packages"
  ];
  darwinNames = [
    "watchexec"
    "brew-nix"
  ];
  expectedNames = commonNames ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin darwinNames;
  watchexecPin = pkgs.lib.importJSON ../pins/watchexec.json;
in
{
  testOverlayOrder = {
    expr = overlayPlan.names;
    expected = expectedNames;
  };

  testOverlayCountMatchesNames = {
    expr = builtins.length overlayPlan.overlays;
    expected = builtins.length expectedNames;
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
