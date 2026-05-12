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
      hackgen-nf-font
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      aqua-voice
      azookey
      codex-app
    ]);
}
