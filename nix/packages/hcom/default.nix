{
  callPackage,
  hcomSource,
  hcomPin ? builtins.fromJSON (builtins.readFile ../../pins/hcom.json),
}:
let
  callFamilyPart = import ../call-family-part.nix { inherit callPackage; };
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
