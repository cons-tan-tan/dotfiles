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
    environment.AGENT_BROWSER_UPDATE_TEST_FIXTURE = "1";
    requiredEnvironment = [ "AGENT_BROWSER_UPDATE_TEST_FIXTURE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/browser/_tests/update-script.bats" ];
    sourceFiles = [
      "modules/features/agents/_tests/paired-release-update-helper.bash"
      "modules/features/agents/browser/_scripts/update.sh"
    ];
  };
}
