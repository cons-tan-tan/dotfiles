{ pkgs, ... }:
{
  # macOS-specific packages
  home.packages =
    with pkgs;
    [
      # nixpkgs packages (macOS only)
      dotfilesPackages.codex-app
      dotfilesPackages.sleepctl
      raycast
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    # システム統合を伴う cask は darwin/system.nix の homebrew.casks 側
    ++ (with pkgs.brewCasks; [
      aqua-voice
      zed
    ]);
}
