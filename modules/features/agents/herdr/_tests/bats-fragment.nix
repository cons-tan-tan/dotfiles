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
    nativeBuildInputs = [ testPackage ];
    environment.HERDR_WRAPPER_TEST_PACKAGE = testPackage;
    requiredEnvironment = [ "HERDR_WRAPPER_TEST_PACKAGE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/herdr/_tests/herdr-wrapper.bats" ];
    sourceFiles = [ "modules/features/agents/herdr/_packages/herdr/herdr-wrapper.sh" ];
  };
}
