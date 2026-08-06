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
    environment.SHELLFIRM_UPDATE_TEST_FIXTURE = "1";
    requiredEnvironment = [ "SHELLFIRM_UPDATE_TEST_FIXTURE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/base/_tests/update-shellfirm.bats" ];
    sourceFiles = [ "modules/features/agents/base/_scripts/update-shellfirm.sh" ];
  };
}
