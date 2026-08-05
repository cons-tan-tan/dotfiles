let
  overlay = import ../_overlays {
    mkPinnedAsset =
      {
        pin,
        system,
        ...
      }:
      {
        asset = pin.assets.${system};
      };
    pin = {
      version = "1.2.3";
      assets.aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-test";
      };
    };
  };
  result = overlay { marker = "final"; } {
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
  testDerivesMetadataFromPreviousPackage = {
    expr = result.watchexec.meta.origin;
    expected = "prev";
  };

  testUsesPinnedReleaseAsset = {
    expr = result.watchexec.src.url;
    expected = "https://github.com/watchexec/watchexec/releases/download/v1.2.3/watchexec-1.2.3-aarch64-apple-darwin.tar.xz";
  };
}
