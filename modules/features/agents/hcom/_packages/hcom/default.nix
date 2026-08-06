{
  agentConfigHelper,
  callPackage,
  ghApiGet,
  hcomSource,
  hcomPin ? builtins.fromJSON (builtins.readFile ./pin.json),
  mkPinnedAsset,
}:
let
  callFamilyPart =
    path: args:
    removeAttrs (callPackage path args) [
      "override"
      "overrideDerivation"
    ];
  package = callPackage ./package.nix {
    inherit
      ghApiGet
      hcomPin
      hcomSource
      mkPinnedAsset
      ;
  };
in
{
  inherit package;
  integrations = callFamilyPart ./integrations.nix {
    inherit agentConfigHelper;
    hcom = package;
  };
}
