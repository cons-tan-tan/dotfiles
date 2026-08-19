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
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      testPackage
    ];
    environment = {
      CLAUDE_UPDATE_TEST_FIXTURE = "1";
      CLAUDE_WRAPPER_TEST_PACKAGE = testPackage;
    };
    requiredEnvironment = [
      "CLAUDE_UPDATE_TEST_FIXTURE"
      "CLAUDE_WRAPPER_TEST_PACKAGE"
    ];
  };
  shard = {
    testFiles = [
      "modules/features/agents/claude/_tests/claude-hooks-migration.bats"
      "modules/features/agents/claude/_tests/claude-wrapper.bats"
      "modules/features/agents/claude/_tests/update-settings-schema.bats"
    ];
    sourceFiles = [
      "modules/features/agents/claude/_scripts/migrate-hooks-directory.sh"
      "modules/features/agents/claude/_packages/claude-code/claude-wrapper.sh"
      "modules/features/agents/claude/_scripts/update-settings-schema.sh"
    ];
  };
}
