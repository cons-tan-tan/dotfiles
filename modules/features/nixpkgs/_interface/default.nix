let
  agentOverlays = import ../../agents/_interface/overlays.nix;
  localPackageRegistry = import ../_registry.nix;
  mozuku = import ../../development/mozuku/_interface.nix;
  watchexec = import ../../development/watchexec/_interface.nix;
  watchexecOverlay = watchexec.mkOverlay {
    mkPinnedAsset = import ../_lib/mk-pinned-asset.nix;
  };
  mkOverlayPlan =
    { inputs, system }:
    import ./overlay-plan.nix {
      inherit inputs localPackageRegistry watchexecOverlay;
      llmAgentsOverlay = agentOverlays.llmAgents;
      mozukuOverlay = mozuku.overlay;
    } system;
in
{
  inherit mkOverlayPlan;

  mkPkgs =
    args:
    import ../_lib/mk-pkgs.nix (
      args
      // {
        inherit mkOverlayPlan;
      }
    );
}
