{
  getEnv,
  getFlake,
  repoRoot,
  system,
}:
let
  flake = getFlake (toString repoRoot);
  pkgs = (import (repoRoot + "/modules/features/nixpkgs/_interface")).mkPkgs {
    inputs = flake.inputs;
    unfreePackageNames = [ "codex-app" ];
  } system;
  updatePins = import (repoRoot + "/modules/features/update-pins/_interface");
  packageName = getEnv "UPDATE_PINS_PACKAGE";
  pinOverride = getEnv "UPDATE_PINS_PIN_OVERRIDE";
  dependencyHashField = getEnv "UPDATE_PINS_DEPENDENCY_HASH_FIELD";
  expectedDependencyProvenance = builtins.fromJSON (getEnv "UPDATE_PINS_DEPENDENCY_PROVENANCE_JSON");
  rawPin = builtins.fromJSON (getEnv "UPDATE_PINS_PIN_JSON");
in
updatePins.mkCandidatePackage {
  inherit
    pkgs
    packageName
    pinOverride
    dependencyHashField
    expectedDependencyProvenance
    rawPin
    ;
}
