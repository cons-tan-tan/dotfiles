{ lib, pkgs }:
let
  herdrFixture = pkgs.writeShellApplication {
    name = "herdr";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$@" >"$TEST_TMPDIR/package-args"
    '';
  };
  sleepFixture = pkgs.writeShellApplication {
    name = "herdr-sleep-fixture";
    text = "exit 0";
  };
  testPackage = pkgs.callPackage ../_packages/herdr/wrapped-package.nix {
    herdr = herdrFixture;
    sleepBin = lib.getExe sleepFixture;
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      pkgs.yq-go
      testPackage
    ];
    environment = {
      HERDR_UPDATE_TEST_FIXTURE = "1";
      HERDR_WRAPPER_TEST_PACKAGE = testPackage;
      HERDR_SKILL_TEST_PACKAGE = pkgs.dotfilesPackages.herdr.agent.skill;
      HERDR_SKILL_TEST_SOURCE = pkgs.dotfilesPackages.herdr.agent.skill.src;
    };
    requiredEnvironment = [
      "HERDR_UPDATE_TEST_FIXTURE"
      "HERDR_WRAPPER_TEST_PACKAGE"
      "HERDR_SKILL_TEST_PACKAGE"
      "HERDR_SKILL_TEST_SOURCE"
    ];
  };
  shard = {
    testFiles = [
      "modules/features/agents/herdr/_tests/herdr-wrapper.bats"
      "modules/features/agents/herdr/_tests/herdr-skill.bats"
      "modules/features/agents/herdr/_tests/update-script.bats"
    ];
    sourceFiles = [
      "modules/features/agents/herdr/_packages/herdr/herdr-wrapper.sh"
      "modules/features/agents/herdr/_scripts/update.sh"
    ];
  };
}
