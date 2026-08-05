{ lib, pkgs }:
let
  drawioFixture = pkgs.writeShellApplication {
    name = "drawio";
    text = "exit 99";
  };
  testPackage = pkgs.callPackage ../_packages/drawio-headless {
    drawio = drawioFixture;
  };
in
{
  fixture = {
    nativeBuildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux testPackage;
    environment.DRAWIO_WRAPPER_TEST_PACKAGE =
      if pkgs.stdenv.hostPlatform.isLinux then testPackage else "";
    requiredEnvironment = lib.optional pkgs.stdenv.hostPlatform.isLinux "DRAWIO_WRAPPER_TEST_PACKAGE";
  };
  shard = {
    testFiles = [ "modules/features/platform/linux/drawio-headless/_tests/drawio-headless.bats" ];
    sourceFiles = [
      "modules/features/platform/linux/drawio-headless/_packages/drawio-headless/drawio-wrapper.sh"
    ];
  };
}
