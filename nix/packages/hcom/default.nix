{
  callPackage,
  hcomSource,
  hcomPin ? builtins.fromJSON (builtins.readFile ../../pins/hcom.json),
}:
let
  callFamilyPart = import ../call-family-part.nix { inherit callPackage; };
  agentConfigHelper = callPackage ../../libexec/agent-config-helper { };
  package = callPackage ./package.nix {
    inherit hcomPin hcomSource;
  };
in
{
  inherit package;
  integrations = callFamilyPart ./integrations.nix {
    inherit agentConfigHelper;
    hcom = package;
  };
}
