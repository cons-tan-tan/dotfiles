{ pkgs, lib, ... }:
{
  # macOS-specific packages
  home.packages =
    with pkgs;
    [
      # nixpkgs packages (macOS only)
      ghostty-bin
      raycast
      zed-editor
      R
      rstudio
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      aqua-voice
      azookey
    ]);
}
