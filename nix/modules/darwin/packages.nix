{ pkgs, ... }:
{
  # macOS-specific packages
  home.packages =
    with pkgs;
    [
      # nixpkgs packages (macOS only)
      codex-app
      raycast
      hackgen-nf-font # ghostty 用フォント (nix/modules/darwin/programs/ghostty.nix)
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    # システム統合を伴う cask は darwin/system.nix の homebrew.casks 側
    ++ (with pkgs.brewCasks; [
      aqua-voice
      zed
    ]);
}
