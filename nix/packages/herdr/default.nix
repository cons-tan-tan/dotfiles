{
  callPackage,
  herdrPin ? builtins.fromJSON (builtins.readFile ../../pins/herdr.json),
}:
let
  callFamilyPart =
    path: args:
    builtins.removeAttrs (callPackage path args) [
      "override"
      "overrideDerivation"
    ];
  build = callPackage ./package.nix {
    inherit herdrPin;
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
