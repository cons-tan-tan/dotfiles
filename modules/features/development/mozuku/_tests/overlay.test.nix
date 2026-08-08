let
  overlay = (import ../_interface.nix).overlay {
    inputs.mozuku.packages = {
      "test-system".default = "selected-mozuku";
      "other-system".default = "other-mozuku";
    };
  };
  result = overlay { marker = "final"; } {
    stdenv.hostPlatform.system = "test-system";
  };
in
{
  testMozukuOnlyExposesLspPackage = {
    expr = builtins.attrNames result;
    expected = [ "mozuku-lsp" ];
  };

  testMozukuUsesHostSystemPackage = {
    expr = result.mozuku-lsp;
    expected = "selected-mozuku";
  };
}
