_: {
  features.platform-darwin-fonts = {
    name = "feature/platform/darwin/fonts";
    darwin = { pkgs, ... }: {
      fonts.packages = with pkgs; [
        hackgen-nf-font
        nerd-fonts.symbols-only
      ];
    };
  };
}
