let
  localPackagesOverlay = import ./local-packages.nix {
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

  watchexecOverlay = import ./watchexec.nix {
    pin = {
      version = "1.2.3";
      assets.aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-test";
      };
    };
  };
  watchexecResult = watchexecOverlay { marker = "final"; } {
    lib = {
      optionalAttrs = condition: attrs: if condition then attrs else { };
      sourceTypes.binaryNativeCode = "binary";
    };
    stdenv.hostPlatform = {
      system = "aarch64-darwin";
      isDarwin = true;
    };
    stdenvNoCC.mkDerivation = attrs: attrs;
    fetchurl = attrs: attrs;
    watchexec.meta.origin = "prev";
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

  testWatchexecDerivesMetadataFromPreviousPackage = {
    expr = watchexecResult.watchexec.meta.origin;
    expected = "prev";
  };

  testWatchexecUsesPinnedReleaseAsset = {
    expr = watchexecResult.watchexec.src.url;
    expected = "https://github.com/watchexec/watchexec/releases/download/v1.2.3/watchexec-1.2.3-aarch64-apple-darwin.tar.xz";
  };
}
