{ pkgs }:
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = with pkgs; [
      coreutils
      git
      jq
    ];
    environment.WATCHEXEC_UPDATE_TEST_FIXTURE = "1";
    requiredEnvironment = [ "WATCHEXEC_UPDATE_TEST_FIXTURE" ];
  };
  shard = {
    testFiles = [ "modules/features/development/watchexec/_tests/update-script.bats" ];
    sourceFiles = [ "modules/features/development/watchexec/_scripts/update.sh" ];
  };
}
