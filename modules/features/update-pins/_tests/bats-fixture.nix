{
  lib,
  pkgs,
  subjects,
}:
let
  updatePinRegistry = import ./registry.nix { inherit lib; };
  testRegistry = pkgs.writeText "update-pins-test-registry.json" (
    builtins.toJSON updatePinRegistry.fixture
  );
in
{
  nativeBuildInputs = [
    pkgs.git
    pkgs.gnutar
    pkgs.gzip
    pkgs.jq
    pkgs.zip
    subjects.updatePinsCore
  ];
  environment.UPDATE_PINS_TEST_BIN = lib.getExe subjects.updatePinsCore;
  environment.UPDATE_PINS_TEST_REGISTRY = testRegistry;
  requiredEnvironment = [
    "UPDATE_PINS_TEST_BIN"
    "UPDATE_PINS_TEST_REGISTRY"
  ];
}
