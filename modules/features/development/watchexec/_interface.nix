{
  overlaySource = ./_overlays/default.nix;
  mkOverlay =
    { mkPinnedAsset }:
    import ./_overlays { inherit mkPinnedAsset; };
  pin = builtins.fromJSON (builtins.readFile ./_overlays/pin.json);
}
