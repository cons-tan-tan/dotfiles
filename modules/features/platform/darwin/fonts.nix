_: {
  flake.modules.darwin.platform-darwin-fonts = { pkgs, ... }: {
    key = "modules/features/platform/darwin/fonts.nix#darwin.platform-darwin-fonts";

    fonts.packages = with pkgs; [
      hackgen-nf-font
      nerd-fonts.symbols-only
    ];
  };
}
