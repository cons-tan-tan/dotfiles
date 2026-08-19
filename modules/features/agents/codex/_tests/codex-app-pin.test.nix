{ lib }:
let
  packageSource = ../_packages/codex-app/default.nix;
  pin = {
    version = "99.88.77";
    appcast = "https://example.invalid/appcast.xml";
    url = "https://example.invalid/Codex.zip";
    hash = "sha256-codex-marker";
    appName = "CodexMarker.app";
    bundleIdentifier = "example.codex-marker";
    displayName = "Codex Marker";
  };
  mkPackage =
    args:
    import packageSource (
      {
        inherit lib;
        stdenvNoCC.mkDerivation = attrs: attrs;
        fetchurl = attrs: attrs;
        unzip = "unzip";
      }
      // args
    );
  injectedPackage = mkPackage { inherit pin; };
  defaultPin = lib.importJSON ../_packages/codex-app/pin.json;
  defaultPackage = mkPackage { };
  describe = package: {
    inherit (package) version;
    inherit (package.src) url hash;
  };
in
{
  testCodexAppPinPropagates = {
    expr = {
      injected = describe injectedPackage;
      default = describe defaultPackage;
      installsInjectedApp = lib.hasInfix pin.appName injectedPackage.installPhase;
    };
    expected = {
      injected = {
        inherit (pin) version url hash;
      };
      default = {
        inherit (defaultPin) version url hash;
      };
      installsInjectedApp = true;
    };
  };
}
