{ lib, pkgs }:
let
  realpathFixture = pkgs.writeShellApplication {
    name = "realpath";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-realpath.args"
      printf '%s\n' "/package/resolved path"
    '';
  };
  wslpathFixture = pkgs.writeShellApplication {
    name = "wslpath";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-wslpath.args"
      printf '%s\n' 'Z:\package\resolved path'
    '';
  };
  handlerFixture = pkgs.writeShellApplication {
    name = "rundll32.exe";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf '%s\n' "$#" "$@" >"$TEST_TMPDIR/package-handler.args"
    '';
  };
  testPackage = pkgs.callPackage ../_packages/wsl-open {
    realpathBin = lib.getExe realpathFixture;
    rundll32Bin = lib.getExe handlerFixture;
    wslpathBin = lib.getExe wslpathFixture;
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ testPackage ];
    environment.WSL_OPEN_TEST_PACKAGE = testPackage;
    requiredEnvironment = [ "WSL_OPEN_TEST_PACKAGE" ];
  };
  shard = {
    testFiles = [ "modules/features/platform/wsl-open/_tests/wsl-open.bats" ];
    sourceFiles = [ "modules/features/platform/wsl-open/_packages/wsl-open/wsl-open.sh" ];
  };
}
