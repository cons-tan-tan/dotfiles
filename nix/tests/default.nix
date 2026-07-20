{
  lib,
  pkgs,
  username,
  reservedCheckNames ? [ ],
}:
let
  nixRoot = ../.;
  repoRoot = ../..;
  testSuffix = ".test.nix";

  # 評価だけで完結するテストは実装の隣に置き、ファイル名から checks の
  # 名前を生成する。
  testFiles = builtins.filter (path: lib.hasSuffix testSuffix (builtins.baseNameOf path)) (
    lib.filesystem.listFilesRecursive nixRoot
  );

  testStem = path: lib.removeSuffix testSuffix (builtins.baseNameOf path);
  checkName = path: "${testStem path}-tests";
  discoveredCheckNames = map checkName testFiles;
  checkNames = discoveredCheckNames ++ builtins.attrNames fixedChecks ++ reservedCheckNames;
  duplicateCheckNames = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) checkNames) > 1
  ) (lib.unique checkNames);

  testContext = {
    inherit lib pkgs username;
  };

  # *.test.nix は lib.runTests 互換の生テスト attrset、またはそれを返す
  # attrset 引数関数とする。必要と宣言した引数だけを共通 context から渡す。
  loadSuite =
    path:
    let
      imported = import path;
    in
    if builtins.isFunction imported then
      imported (builtins.intersectAttrs (builtins.functionArgs imported) testContext)
    else
      imported;

  validateSuite =
    path: suite:
    if !builtins.isAttrs suite then
      throw "${toString path} must return an attribute set"
    else
      let
        names = builtins.attrNames suite;
        invalidNames = builtins.filter (name: !lib.hasPrefix "test" name) names;
        invalidCases = builtins.filter (
          name:
          let
            testCase = suite.${name};
          in
          !(builtins.isAttrs testCase && testCase ? expr && testCase ? expected)
        ) names;
      in
      if names == [ ] then
        throw "${toString path} does not define any tests"
      else if invalidNames != [ ] then
        throw "${toString path} contains non-test attributes: ${builtins.toJSON invalidNames}"
      else if invalidCases != [ ] then
        throw "${toString path} contains invalid test cases: ${builtins.toJSON invalidCases}"
      else
        null;

  mkEvalCheck =
    path:
    let
      suite = loadSuite path;
      validation = validateSuite path suite;
      failures = lib.debug.runTests suite;
      result = lib.debug.throwTestFailures { inherit failures; };
      name = checkName path;
    in
    {
      inherit name;
      value = builtins.seq validation (builtins.seq result (pkgs.runCommand name { } ''touch "$out"''));
    };

  evalChecks = lib.listToAttrs (map mkEvalCheck testFiles);

  fixedChecks = {
    merge-py-tests =
      pkgs.runCommand "merge-py-tests"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (ps: [
              ps.pytest
              ps.tomlkit
            ]))
          ];
        }
        ''
          cp -R ${../modules/home/programs/codex} codex
          chmod -R u+w codex
          cd codex
          pytest -q
          touch "$out"
        '';

    bats-tests =
      pkgs.runCommand "bats-tests"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.bats
            pkgs.git
            pkgs.gnutar
            pkgs.gzip
            pkgs.jq
            pkgs.python3
          ];
        }
        ''
          cp -R ${repoRoot} repo
          chmod -R u+w repo
          cd repo
          git init -q
          bats --print-output-on-failure tests/
          touch "$out"
        '';
  };
in
# checks は右辺優先で結合されるため、呼び出し元の予約名も含めて検査し、
# suite や既存 gate が暗黙に上書きされる前に失敗させる。
if duplicateCheckNames != [ ] then
  throw "duplicate test check names: ${builtins.toJSON duplicateCheckNames}"
else
  evalChecks // fixedChecks
