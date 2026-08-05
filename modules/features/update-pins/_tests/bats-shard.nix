{ lib }:
let
  updatePinRegistry = import ./registry.nix { inherit lib; };
in
{
  name = "update-pins-e2e";
  fixture = "updatePins";
  testFiles = [ "modules/features/update-pins/_tests/update-pins.bats" ];
  sourceFiles = updatePinRegistry.sourceFiles ++ [
    "modules/features/agents/hunk/default.nix"
    "modules/features/checks/_lib/bats/test-helper.bash"
  ];
  initializeGit = true;
  platformPredicate = _platform: true;
}
