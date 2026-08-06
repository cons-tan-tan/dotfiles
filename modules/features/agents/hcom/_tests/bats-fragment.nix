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
    environment.HCOM_UPDATE_TEST_FIXTURE = "1";
    requiredEnvironment = [ "HCOM_UPDATE_TEST_FIXTURE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/hcom/_tests/update-script.bats" ];
    sourceFiles = [
      "modules/features/agents/_tests/paired-release-update-helper.bash"
      "modules/features/agents/hcom/_scripts/update.sh"
    ];
  };
}
