{
  name = "direnv-local-integration";
  fixture = "direnvLocal";
  testFiles = [ "modules/features/shell/_tests/direnv-local.bats" ];
  sourceFiles = [ "modules/features/checks/_interface/bats/test-helper.bash" ];
  initializeGit = false;
  platformPredicate = _platform: true;
}
