{ pkgs }:
let
  piFixture = pkgs.writeShellApplication {
    name = "pi";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'package:%s\nskip:%s\ntelemetry:%s\n' \
        "$PI_PACKAGE_DIR" "$PI_SKIP_VERSION_CHECK" "$PI_TELEMETRY" >"$TEST_TMPDIR/result"
      printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
    '';
  };
  managedPackageFixture = pkgs.runCommand "pi-managed-package-fixture" { } ''
    mkdir -p "$out"
  '';
  testPackage = pkgs.callPackage ../_packages/pi/wrapped-package.nix {
    packageDir = managedPackageFixture;
    pi = piFixture;
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ testPackage ];
    environment.PI_WRAPPER_TEST_PACKAGE = testPackage;
    requiredEnvironment = [ "PI_WRAPPER_TEST_PACKAGE" ];
  };
  shard = {
    testFiles = [
      "modules/features/agents/pi/_tests/pi-package-manager.bats"
      "modules/features/agents/pi/_tests/pi-wrapper.bats"
    ];
    sourceFiles = [
      "modules/features/agents/pi/_packages/pi/package-manager.sh"
      "modules/features/agents/pi/_packages/pi/pi-wrapper.sh"
    ];
  };
}
