{ pkgs }:
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ pkgs.coreutils ];
    environment = { };
    requiredEnvironment = [ ];
  };
  shard = {
    testFiles = [ "modules/features/trash/_tests/prepare-trash-directory.bats" ];
    sourceFiles = [ "modules/features/trash/_scripts/prepare-trash-directory.sh" ];
  };
}
