{ pkgs }:
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ pkgs.git ];
    environment = { };
    requiredEnvironment = [ ];
  };
  shard = {
    testFiles = [ "modules/features/source-control/ghq-sync/_tests/ghq-fetch-all.bats" ];
    sourceFiles = [
      "modules/features/source-control/ghq-sync/_packages/fetch-all/ghq-fetch-all.sh"
    ];
  };
}
