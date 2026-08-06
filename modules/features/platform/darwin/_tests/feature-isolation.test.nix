let
  fontsFeature = (import ../fonts.nix null).features.platform-darwin-fonts;
  touchIdFeature = (import ../touch-id.nix null).features.platform-darwin-touch-id;
  fontPackages = {
    hackgen-nf-font = "hackgen";
    nerd-fonts.symbols-only = "symbols-only";
  };
  fontsContribution = fontsFeature.darwin { pkgs = fontPackages; };
in
{
  testFontsOwnOnlyFontConfiguration = {
    expr = {
      packages = fontsContribution.fonts.packages;
      ownsSecurity = fontsContribution ? security;
    };
    expected = {
      packages = [
        "hackgen"
        "symbols-only"
      ];
      ownsSecurity = false;
    };
  };

  testTouchIdOwnsItsPamConfiguration = {
    expr = touchIdFeature.darwin.security.pam.services.sudo_local.touchIdAuth;
    expected = true;
  };
}
