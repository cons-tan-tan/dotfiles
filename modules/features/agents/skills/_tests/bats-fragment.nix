{ pkgs }:
let
  profiles = import ./commit-profiles-fixture.nix { inherit pkgs; };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ pkgs.ghq ];
    environment.COMMIT_PROFILE_TEST_SELECTOR = pkgs.lib.getExe profiles.selector;
    requiredEnvironment = [ "COMMIT_PROFILE_TEST_SELECTOR" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/skills/_tests/commit-profiles.bats" ];
    sourceFiles = [ "modules/features/agents/skills/_packages/commit-profiles/select-profile.sh" ];
  };
}
