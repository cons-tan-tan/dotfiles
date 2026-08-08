{
  name = "update-pins-runner";
  fixture = "updatePins";
  testFiles = [ "modules/features/update-pins/_tests/update-pins.bats" ];
  sourceFiles = [
    "modules/features/checks/_interface/bats/test-helper.bash"
    "modules/features/update-pins/_interface/app-set.nix"
    "modules/features/update-pins/_scripts/update-pins.sh"
  ];
  initializeGit = true;
  platformPredicate = _platform: true;
}
