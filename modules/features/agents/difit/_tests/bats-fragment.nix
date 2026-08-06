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
    environment.DIFIT_UPDATE_TEST_FIXTURE = "1";
    requiredEnvironment = [ "DIFIT_UPDATE_TEST_FIXTURE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/difit/_tests/update-script.bats" ];
    sourceFiles = [ "modules/features/agents/difit/_scripts/update.sh" ];
  };
}
