{
  ciCheck,
  inputs,
  lib,
  pkgs,
  repoRoot,
}:
let
  duplicateValues =
    values:
    builtins.filter (value: builtins.length (builtins.filter (other: other == value) values) > 1) (
      lib.unique values
    );

  validFragment =
    fragment:
    builtins.isString fragment
    && builtins.match "[[:space:]]*" fragment == null
    && !lib.hasInfix "\n" fragment
    && builtins.stringLength fragment <= 256;

  validateFixture =
    path: fixture:
    if !builtins.isAttrs fixture then
      throw "${toString path} must return an attribute set"
    else
      let
        rootNames = builtins.attrNames fixture;
        meta = fixture.meta or null;
        tests = fixture.tests or null;
        failureCases = fixture.failureCases or null;
        testNames = if builtins.isAttrs tests then builtins.attrNames tests else [ ];
        failureCaseNames = if builtins.isAttrs failureCases then builtins.attrNames failureCases else [ ];
        invalidTestNames = builtins.filter (name: !lib.hasPrefix "test" name) testNames;
        invalidTests = builtins.filter (
          name:
          let
            testCase = tests.${name};
          in
          !(
            builtins.isAttrs testCase
            &&
              builtins.attrNames testCase == [
                "expected"
                "expr"
              ]
          )
        ) testNames;
        invalidFailureNames = builtins.filter (
          name: builtins.match "^[a-z][A-Za-z0-9]*$" name == null
        ) failureCaseNames;
        invalidFailureCases = builtins.filter (
          name:
          let
            testCase = failureCases.${name};
          in
          !(
            builtins.isAttrs testCase
            &&
              builtins.attrNames testCase == [
                "expectedFragments"
                "expression"
              ]
            && builtins.isList testCase.expectedFragments
            && testCase.expectedFragments != [ ]
            && builtins.all validFragment testCase.expectedFragments
          )
        ) failureCaseNames;
      in
      if
        rootNames != [
          "failureCases"
          "meta"
          "tests"
        ]
      then
        throw "${toString path} must contain exactly failureCases, meta, and tests"
      else if
        !(builtins.isAttrs meta)
        ||
          builtins.attrNames meta != [
            "checkName"
            "execution"
            "hestiaGroup"
          ]
        || !(builtins.isString meta.checkName)
        || builtins.match "^[a-z0-9][a-z0-9-]*$" meta.checkName == null
        || !(builtins.elem meta.execution [
          "build"
          "evaluation-complete"
        ])
        || (meta.execution == "build" && (!(builtins.isString meta.hestiaGroup) || meta.hestiaGroup == ""))
        || (meta.execution == "evaluation-complete" && meta.hestiaGroup != null)
      then
        throw "${toString path} has invalid Den suite metadata"
      else if !builtins.isAttrs tests || testNames == [ ] then
        throw "${toString path} must define at least one positive test"
      else if invalidTestNames != [ ] then
        throw "${toString path} contains invalid positive test names: ${builtins.toJSON invalidTestNames}"
      else if invalidTests != [ ] then
        throw "${toString path} contains invalid positive tests: ${builtins.toJSON invalidTests}"
      else if !builtins.isAttrs failureCases then
        throw "${toString path} failureCases must be an attribute set"
      else if meta.execution == "evaluation-complete" && failureCaseNames != [ ] then
        throw "${toString path} evaluation-complete suites cannot define failure cases"
      else if invalidFailureNames != [ ] then
        throw "${toString path} contains invalid failure case names: ${builtins.toJSON invalidFailureNames}"
      else if invalidFailureCases != [ ] then
        throw "${toString path} contains invalid failure cases: ${builtins.toJSON invalidFailureCases}"
      else
        null;

  loadEntry =
    path:
    let
      fixture = import path {
        caseName = null;
        inherit inputs lib repoRoot;
      };
      validation = validateFixture path fixture;
    in
    builtins.seq validation { inherit fixture path; };

  validateSuiteIdentities =
    entries:
    let
      paths = map (entry: toString entry.path) entries;
      checkNames = map (entry: entry.fixture.meta.checkName) entries;
      duplicatePaths = duplicateValues paths;
      duplicateCheckNames = duplicateValues checkNames;
    in
    if duplicatePaths != [ ] then
      throw "Den suite paths must be unique: ${builtins.toJSON duplicatePaths}"
    else if duplicateCheckNames != [ ] then
      throw "Den suite check names must be unique: ${builtins.toJSON duplicateCheckNames}"
    else
      null;

  mkCheck =
    entry:
    let
      inherit (entry) fixture path;
      inherit (fixture.meta) checkName execution hestiaGroup;
      positiveResult = lib.debug.throwTestFailures {
        failures = lib.debug.runTests fixture.tests;
      };
      failureCaseNames = builtins.attrNames fixture.failureCases;
      suiteRelativePath = lib.removePrefix "${toString repoRoot}/" (toString path);
      failureRunner = builtins.toFile "den-suite-failure-case.nix" ''
        { caseName }:
        let
          lib = import (${inputs.nixpkgs.outPath} + "/lib");
          pkgs = import ${inputs.nixpkgs.outPath} { system = "x86_64-linux"; };
          nixosSystem = args: import (${inputs.nixpkgs.outPath} + "/nixos/lib/eval-config.nix") (
            {
              inherit lib;
              system = null;
            }
            // args
          );
          inputs = {
            den = import (${inputs.den.outPath} + "/nix");
            "gen-schema".lib = import (${inputs.den-gen-schema.outPath} + "/nix/lib") {
              inherit lib;
              inputs."gen-algebra" = import ${inputs.den-gen-algebra.outPath} { inherit lib; };
            };
            "nix-effects".lib = import ${inputs.den-nix-effects.outPath} { inherit lib; };
            home-manager.lib = import (${inputs.home-manager.outPath} + "/lib") { inherit lib; };
            nixpkgs = {
              lib = lib // { inherit nixosSystem; };
              legacyPackages.x86_64-linux = pkgs;
            };
          };
        in
        import ${repoRoot}/${suiteRelativePath} {
          inherit caseName inputs lib;
          repoRoot = ${repoRoot};
        }
      '';
      runFailureCases = lib.concatMapStringsSep "\n" (
        name:
        let
          checkExpectedFragments = lib.concatMapStringsSep "\n" (expectedFragment: ''
            if ! rg --fixed-strings --quiet -- ${lib.escapeShellArg expectedFragment} "$TMPDIR/${name}.diagnostic"; then
              printf 'unexpected Den suite diagnostic: %s\n' ${lib.escapeShellArg name} >&2
              printf 'expected fragment: %s\n' ${lib.escapeShellArg expectedFragment} >&2
              head -c 4096 "$TMPDIR/${name}.diagnostic" >&2
              printf '\n' >&2
              exit 1
            fi
          '') fixture.failureCases.${name}.expectedFragments;
        in
        ''
          if nix-instantiate \
            --log-format internal-json \
            --eval \
            --strict \
            ${failureRunner} \
            --argstr caseName ${lib.escapeShellArg name} \
            >"$TMPDIR/${name}.stdout" \
            2>"$TMPDIR/${name}.stderr"; then
            printf 'expected Den suite fixture to fail: %s\n' ${lib.escapeShellArg name} >&2
            exit 1
          fi

          if ! jq --raw-input --raw-output --slurp '
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
          ' "$TMPDIR/${name}.stderr" >"$TMPDIR/${name}.diagnostic"; then
            printf 'could not extract root Den suite diagnostic: %s\n' ${lib.escapeShellArg name} >&2
            head -c 4096 "$TMPDIR/${name}.stderr" >&2
            printf '\n' >&2
            exit 1
          fi

          ${checkExpectedFragments}
        ''
      ) failureCaseNames;
      check = builtins.seq positiveResult (
        pkgs.runCommand checkName
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.nix
              pkgs.ripgrep
            ];
          }
          ''
            set -euo pipefail
            export NIX_STATE_DIR="$TMPDIR/nix-state"
            export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
            mkdir -p "$NIX_STATE_DIR/profiles/per-user" "$XDG_CACHE_HOME"
            ${runFailureCases}
            touch "$out"
          ''
      );
    in
    {
      name = checkName;
      inherit execution;
      value = check;
      buildEntry = ciCheck.buildEntry (ciCheck.targets.linux hestiaGroup) check;
    };

  producer =
    files:
    let
      entries = map loadEntry files;
      identitiesValid = validateSuiteIdentities entries;
      checks = map mkCheck entries;
      evaluationCompleteChecks = lib.listToAttrs (
        map (check: {
          inherit (check) name value;
        }) (builtins.filter (check: check.execution == "evaluation-complete") checks)
      );
      buildEntries = lib.listToAttrs (
        map (check: {
          inherit (check) name;
          value = check.buildEntry;
        }) (builtins.filter (check: check.execution == "build") checks)
      );
    in
    builtins.seq identitiesValid { inherit buildEntries evaluationCompleteChecks; };
in
{
  inherit producer validateFixture validateSuiteIdentities;

  checks =
    files:
    let
      result = producer files;
    in
    (ciCheck.mkBuildProducer {
      owner = "Den suites";
      entries = result.buildEntries;
    }).checks
    // ciCheck.evaluationCompleteSet result.evaluationCompleteChecks;
}
