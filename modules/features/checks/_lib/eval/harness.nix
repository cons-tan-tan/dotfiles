{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
  testContext,
  testDiscovery,
}:
let
  inherit (testDiscovery) checkName failureCheckName;
  failureStem = path: lib.removeSuffix ".failure.test.nix" (baseNameOf path);

  validateUniqueCheckNames =
    owner: names:
    let
      duplicates = testDiscovery.duplicateNames names;
    in
    if duplicates == [ ] then
      null
    else
      throw "${owner} produces duplicate check names: ${builtins.toJSON duplicates}";

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

  validateFailureSuite =
    path: suite: suiteArgs: cases:
    let
      names = if builtins.isAttrs cases then builtins.attrNames cases else [ ];
      invalidNames = builtins.filter (name: builtins.match "^[a-z][A-Za-z0-9]*$" name == null) names;
      invalidCases = builtins.filter (
        name:
        let
          testCase = cases.${name};
        in
        !(builtins.isAttrs testCase && testCase ? expression && testCase ? expectedFragment)
      ) names;
      invalidFragments = builtins.filter (
        name:
        let
          fragment = cases.${name}.expectedFragment;
        in
        !(
          builtins.isString fragment
          && builtins.match "[[:space:]]*" fragment == null
          && !lib.hasInfix "\n" fragment
          && builtins.stringLength fragment <= 256
        )
      ) names;
    in
    if !builtins.isFunction suite then
      throw "${toString path} must return a function"
    else if
      builtins.attrNames suiteArgs != [
        "caseName"
        "nixpkgsPath"
        "repoRoot"
      ]
    then
      throw "${toString path} must accept exactly caseName, nixpkgsPath, and repoRoot"
    else if !builtins.isAttrs cases then
      throw "${toString path} must return its failure cases when caseName is null"
    else if names == [ ] then
      throw "${toString path} does not define any failure cases"
    else if invalidNames != [ ] then
      throw "${toString path} contains invalid failure case names: ${builtins.toJSON invalidNames}"
    else if invalidCases != [ ] then
      throw "${toString path} contains invalid failure cases: ${builtins.toJSON invalidCases}"
    else if invalidFragments != [ ] then
      throw "${toString path} contains invalid diagnostic fragments for cases: ${builtins.toJSON invalidFragments}"
    else
      null;

  mkFailureCheck =
    {
      path,
      name ? failureCheckName path,
      suiteStem ? failureStem path,
    }:
    let
      suite = import path;
      suiteArgs = if builtins.isFunction suite then builtins.functionArgs suite else { };
      suiteArgsValid =
        builtins.attrNames suiteArgs == [
          "caseName"
          "nixpkgsPath"
          "repoRoot"
        ];
      # null はmetadata列挙専用。case attrsetを返しても、expression fieldは
      # 遅延値なので親 evaluator では強制されない。
      cases =
        if builtins.isFunction suite && suiteArgsValid then
          suite {
            caseName = null;
            nixpkgsPath = pkgs.path;
            inherit repoRoot;
          }
        else
          null;
      validation = validateFailureSuite path suite suiteArgs cases;
      suiteRelativePath = lib.removePrefix "${toString repoRoot}/" (toString path);
      nixpkgsArgument = "${pkgs.path}";
      repoRootArgument = "${repoRoot}";
      suitePath = "${repoRootArgument}/${suiteRelativePath}";
      runCases = lib.concatMapStringsSep "\n" (
        caseName:
        let
          expectedFragment = cases.${caseName}.expectedFragment;
          caseLabel = "${suiteStem}/${caseName}";
        in
        ''
          case_label=${lib.escapeShellArg caseLabel}
          expected_fragment=${lib.escapeShellArg expectedFragment}
          stdout_file="$TMPDIR/${caseName}.stdout"
          stderr_file="$TMPDIR/${caseName}.stderr"
          diagnostic_file="$TMPDIR/${caseName}.diagnostic"
          parse_error_file="$TMPDIR/${caseName}.parse-error"

          status=0
          if ${pkgs.nix}/bin/nix-instantiate \
            --log-format internal-json \
            --eval \
            --strict \
            ${lib.escapeShellArg suitePath} \
            --argstr caseName ${lib.escapeShellArg caseName} \
            --arg nixpkgsPath ${lib.escapeShellArg nixpkgsArgument} \
            --arg repoRoot ${lib.escapeShellArg repoRootArgument} \
            >"$stdout_file" 2>"$stderr_file"; then
            status=0
          else
            status="$?"
          fi

          if [[ "$status" -eq 0 ]]; then
            printf 'expected evaluation failure but succeeded: %s\n' "$case_label" >&2
            exit 1
          fi

          if ! ${pkgs.jq}/bin/jq --raw-input --raw-output --slurp '
            split("\n")
            | map(select(length > 0)) as $lines
            | if ($lines | length) == 0 then
                error("Nix did not emit a structured diagnostic")
              elif all($lines[]; startswith("@nix ")) then
                $lines
              else
                error("Nix emitted a non-structured diagnostic line")
              end
            | map(ltrimstr("@nix ") | fromjson)
            | map(select(
                .action == "msg"
                and .level == 0
                and (.raw_msg | type) == "string"
              ))
            | if length == 1 then
                .[0].raw_msg
              else
                error("expected exactly one root Nix diagnostic")
              end
            | gsub("\u001b\\[[0-9;]*m"; "")
          ' "$stderr_file" >"$diagnostic_file" 2>"$parse_error_file"; then
            printf 'could not extract root evaluation diagnostic: %s\n' "$case_label" >&2
            ${pkgs.coreutils}/bin/head -c 1024 "$parse_error_file" >&2
            printf '\nbounded stderr follows:\n' >&2
            ${pkgs.coreutils}/bin/head -c 4096 "$stderr_file" >&2
            printf '\n' >&2
            exit 1
          fi

          if ! ${pkgs.ripgrep}/bin/rg \
            --fixed-strings \
            --quiet \
            -- "$expected_fragment" \
            "$diagnostic_file"; then
            printf 'unexpected evaluation failure: %s\n' "$case_label" >&2
            printf 'expected diagnostic fragment: %s\n' "$expected_fragment" >&2
            printf 'bounded stderr follows:\n' >&2
            ${pkgs.coreutils}/bin/head -c 4096 "$stderr_file" >&2
            printf '\n' >&2
            exit 1
          fi
        ''
      ) (builtins.attrNames cases);
    in
    {
      inherit name;
      value = builtins.seq validation (
        pkgs.runCommand name { } ''
          set -euo pipefail
          export HOME="$TMPDIR/home"
          export LC_ALL=C
          export NIX_STATE_DIR="$TMPDIR/nix-state"
          mkdir -p "$HOME" "$NIX_STATE_DIR/profiles/per-user"
          ${runCases}
          touch "$out"
        ''
      );
    };
in
{
  positiveChecks =
    files:
    let
      entries = map mkEvalCheck files;
      uniqueness = validateUniqueCheckNames "positive eval suites" (map (entry: entry.name) entries);
    in
    builtins.seq uniqueness (ciCheck.evaluationCompleteSet (lib.listToAttrs entries));
  failureChecks =
    files:
    let
      entries = map (path: mkFailureCheck { inherit path; }) files;
      uniqueness = validateUniqueCheckNames "failure eval suites" (map (entry: entry.name) entries);
    in
    builtins.seq uniqueness (
      ciCheck.annotateSet (ciCheck.targets.both "eval-tests") (lib.listToAttrs entries)
    );

  isolatedFailureCheck =
    {
      name,
      path,
      suiteStem ? name,
    }:
    (mkFailureCheck {
      inherit name path suiteStem;
    }).value;
}
