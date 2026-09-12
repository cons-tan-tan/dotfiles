{ pkgs }:
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = with pkgs; [
      coreutils
      git
      jq
      perl
      ripgrep
    ];
    environment.BEE_UPDATE_TEST_FIXTURE = "1";
    requiredEnvironment = [ "BEE_UPDATE_TEST_FIXTURE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/bee/_tests/update-script.bats" ];
    sourceFiles = [ "modules/features/agents/bee/_scripts/update.sh" ];
  };
}
