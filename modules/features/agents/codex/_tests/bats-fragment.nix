{ pkgs }:
let
  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      : "''${TEST_TMPDIR:?}"
      printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/result"
    '';
  };
  herdrSkillFixture = pkgs.runCommand "herdr-skill-fixture" { } ''
    mkdir -p "$out"
    touch "$out/SKILL.md"
  '';
  testPackage = pkgs.callPackage ../_packages/codex/wrapped-package.nix {
    codex = codexFixture;
    herdrSkillPath = "${herdrSkillFixture}/SKILL.md";
  };
in
{
  group = "shellWrappers";
  fixture = {
    nativeBuildInputs = [ testPackage ];
    environment.CODEX_WRAPPER_TEST_PACKAGE = testPackage;
    requiredEnvironment = [ "CODEX_WRAPPER_TEST_PACKAGE" ];
  };
  shard = {
    testFiles = [ "modules/features/agents/codex/_tests/codex-wrapper.bats" ];
    sourceFiles = [ "modules/features/agents/codex/_packages/codex/codex-wrapper.sh" ];
  };
}
