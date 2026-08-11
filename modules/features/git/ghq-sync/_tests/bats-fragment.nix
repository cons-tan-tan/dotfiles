{ pkgs }:
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ pkgs.git ];
    environment = { };
    requiredEnvironment = [ ];
  };
  shard = {
    testFiles = [ "modules/features/git/ghq-sync/_tests/ghq-fetch-all.bats" ];
    sourceFiles = [
      "modules/features/git/ghq-sync/_packages/fetch-all/ghq-fetch-all.sh"
    ];
  };
}
