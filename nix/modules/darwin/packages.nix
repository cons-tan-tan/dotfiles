{ pkgs, lib, ... }:
{
  # macOS-specific packages
  home.packages =
    with pkgs;
    [
      # nixpkgs packages (macOS only)
      raycast
      zed-editor
      rstudio
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      aqua-voice
      azookey
    ]);
}
