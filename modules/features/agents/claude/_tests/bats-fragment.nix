{ pkgs }:
let
  claudeFixture = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'path:%s\n' "$PATH" >"$TEST_TMPDIR/result"
      printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
    '';
  };
  herdrPluginFixture = pkgs.runCommand "herdr-plugin-fixture" { } ''
    mkdir -p "$out"
    touch "$out/plugin.json"
  '';
  testPackage = pkgs.callPackage ../_packages/claude-code/wrapped-package.nix {
    claudeCode = claudeFixture;
    herdrPlugin = herdrPluginFixture;
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ testPackage ];
    environment.CLAUDE_WRAPPER_TEST_PACKAGE = testPackage;
    requiredEnvironment = [ "CLAUDE_WRAPPER_TEST_PACKAGE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/claude/_tests/claude-wrapper.bats" ];
    sourceFiles = [ "modules/features/agents/claude/_packages/claude-code/claude-wrapper.sh" ];
  };
}
