{ lib }:
let
  packageSource = ../_packages/shellfirm/default.nix;
  pin = {
    version = "99.88.77";
    srcHash = "sha256-shellfirm-marker";
  };
  mkPackage =
    args:
    import packageSource (
      {
        callPackage = _: _: "shellfirm-updater";
        ghApiGet = "gh-api-get";
        inherit lib;
        rustPlatform.buildRustPackage = attrs: attrs;
        fetchFromGitHub = attrs: attrs;
        pkg-config = "pkg-config";
        openssl = "openssl";
      }
      // args
    );
  injectedPackage = mkPackage { inherit pin; };
  defaultPin = lib.importJSON ../_packages/shellfirm/pin.json;
  defaultPackage = mkPackage { };
in
{
  testShellfirmPinPropagates = {
    expr = {
      injected = {
        inherit (injectedPackage) version;
        rev = injectedPackage.src.rev;
        hash = injectedPackage.src.hash;
      };
      default = {
        inherit (defaultPackage) version;
        rev = defaultPackage.src.rev;
        hash = defaultPackage.src.hash;
      };
    };
    expected = {
      injected = {
        inherit (pin) version;
        rev = "v${pin.version}";
        hash = pin.srcHash;
      };
      default = {
        inherit (defaultPin) version;
        rev = "v${defaultPin.version}";
        hash = defaultPin.srcHash;
      };
    };
  };
}
