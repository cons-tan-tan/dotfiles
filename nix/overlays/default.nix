final: prev:
let
  # Import all overlay files in this directory
  overlayFiles = [
    # AI tools
    ./ai-tools.nix
    # Rust tools
    ./rustup.nix
  ];

  # Apply each overlay and merge results
  applyOverlays = builtins.foldl' (acc: overlay: acc // (import overlay final prev)) { } overlayFiles;
in
applyOverlays
