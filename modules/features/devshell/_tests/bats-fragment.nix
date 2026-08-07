{ lib, pkgs }:
let
  testPackage = pkgs.callPackage ../_packages/nix-mutation-test { };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ testPackage ];
    environment.NIX_MUTATION_TEST_BIN = lib.getExe testPackage;
    requiredEnvironment = [ "NIX_MUTATION_TEST_BIN" ];
  };
  shard = {
    testFiles = [ "modules/features/devshell/_tests/nix-mutation-test.bats" ];
    sourceFiles = [ ];
  };
}
