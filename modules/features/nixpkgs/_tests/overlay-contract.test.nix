let
  localPackagesOverlay = import ../_overlays/local-packages.nix {
    inputs = { };
    registry =
      { pkgs, ... }:
      {
        selectedPackageSet = pkgs.marker;
      };
  };
  localPackagesResult = localPackagesOverlay { marker = "final"; } {
    marker = "prev";
    lib = { };
    stdenv.hostPlatform = { };
  };
in
{
  testLocalPackagesOnlyExposeNamespace = {
    expr = builtins.attrNames localPackagesResult;
    expected = [ "dotfilesPackages" ];
  };

  testLocalPackagesUseFinalPackageSet = {
    expr = localPackagesResult.dotfilesPackages.selectedPackageSet;
    expected = "final";
  };
}
