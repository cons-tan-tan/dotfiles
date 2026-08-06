{
  callPackage,
  ghApiGet,
  herdrPin ? builtins.fromJSON (builtins.readFile ./pin.json),
  mkPinnedAsset,
}:
let
  callFamilyPart =
    path: args:
    removeAttrs (callPackage path args) [
      "override"
      "overrideDerivation"
    ];
  build = callPackage ./package.nix {
    inherit ghApiGet herdrPin mkPinnedAsset;
  };
in
{
  inherit (build) package;

  agent = callFamilyPart ./agent-artifacts.nix {
    inherit (build) platforms src version;
  };

  integrations = callFamilyPart ./integrations.nix {
    herdr = build.package;
    inherit (build) platforms version;
  };

  wrappedPackage = callPackage ./wrapped-package.nix {
    herdr = build.package;
  };
}
