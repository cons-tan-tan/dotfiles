_: {
  flake.modules.darwin.platform-darwin = { pkgs, ... }: {
    key = "modules/features/platform/darwin/fonts.nix#darwin.platform-darwin";

    fonts.packages = with pkgs; [
      hackgen-nf-font
      nerd-fonts.symbols-only
    ];
  };
}
