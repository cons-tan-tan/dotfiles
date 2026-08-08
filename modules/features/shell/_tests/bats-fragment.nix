{ pkgs }:
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ pkgs.ghq ];
    environment = { };
    requiredEnvironment = [ ];
  };
  shard = {
    testFiles = [ "modules/features/shell/_tests/nixbuild-direnvrc.bats" ];
    sourceFiles = [ "modules/features/shell/_data/nixbuild-direnvrc.sh" ];
  };
}
