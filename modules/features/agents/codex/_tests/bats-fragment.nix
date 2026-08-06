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
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      pkgs.libplist
      pkgs.ripgrep
      pkgs.unzip
      pkgs.xmlstarlet
      pkgs.zip
      testPackage
    ];
    environment = {
      CODEX_UPDATE_TEST_FIXTURE = "1";
      CODEX_WRAPPER_TEST_PACKAGE = testPackage;
    };
    requiredEnvironment = [
      "CODEX_UPDATE_TEST_FIXTURE"
      "CODEX_WRAPPER_TEST_PACKAGE"
    ];
  };
  shard = {
    testFiles = [
      "modules/features/agents/codex/_tests/codex-wrapper.bats"
      "modules/features/agents/codex/_tests/update-app.bats"
    ];
    sourceFiles = [
      "modules/features/agents/codex/_packages/codex/codex-wrapper.sh"
      "modules/features/agents/codex/_scripts/update-app.sh"
    ];
  };
}
