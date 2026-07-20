{
  callPackage,
  hcomSource,
  hcomPin ? builtins.fromJSON (builtins.readFile ../../pins/hcom.json),
}:
let
  callFamilyPart =
    path: args:
    builtins.removeAttrs (callPackage path args) [
      "override"
      "overrideDerivation"
    ];
  package = callPackage ./package.nix {
    inherit hcomPin hcomSource;
  };
in
{
  inherit package;
  integrations = callFamilyPart ./integrations.nix {
    hcom = package;
  };
}
