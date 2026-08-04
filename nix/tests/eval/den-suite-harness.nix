{
  checkName ? "den-capability-tests",
  fixturePath ? ../../../modules/_tests/den-capabilities.suite.nix,
  fixtureRoot ? null,
  inputs,
  lib,
  pkgs,
  schemaModule ? null,
}:
let
  fixture = import fixturePath (
    {
      inherit inputs lib;
    }
    // lib.optionalAttrs (schemaModule != null) { inherit schemaModule; }
    // lib.optionalAttrs (fixtureRoot != null) { repoRoot = fixtureRoot; }
  );
  positiveResult = lib.debug.throwTestFailures {
    failures = lib.debug.runTests fixture.tests;
  };
  failureCaseNames = builtins.attrNames fixture.failureCases;
  failureRunner = builtins.toFile "den-capability-failure-case.nix" ''
    { caseName }:
    let
      lib = import (${inputs.nixpkgs.outPath} + "/lib");
      pkgs = import ${inputs.nixpkgs.outPath} { system = "x86_64-linux"; };
      inputs = {
        den = import (${inputs.den.outPath} + "/nix");
        "gen-schema".lib = import (${inputs.den-gen-schema.outPath} + "/nix/lib") {
          inherit lib;
          inputs."gen-algebra" = import ${inputs.den-gen-algebra.outPath} { inherit lib; };
        };
        "nix-effects".lib = import ${inputs.den-nix-effects.outPath} { inherit lib; };
        home-manager.lib = import (${inputs.home-manager.outPath} + "/lib") { inherit lib; };
        nixpkgs = {
          inherit lib;
          legacyPackages.x86_64-linux = pkgs;
        };
      };
    in
    import ${fixturePath} {
      inherit caseName inputs lib;
      ${lib.optionalString (schemaModule != null) "schemaModule = ${schemaModule};"}
      ${lib.optionalString (fixtureRoot != null) "repoRoot = ${fixtureRoot};"}
    }
  '';
  runFailureCases = lib.concatMapStringsSep "\n" (
    name:
    let
      checkExpectedFragments = lib.concatMapStringsSep "\n" (expectedFragment: ''
        if ! rg --fixed-strings --quiet -- ${lib.escapeShellArg expectedFragment} "$TMPDIR/${name}.diagnostic"; then
          printf 'unexpected Den capability diagnostic: %s\n' ${lib.escapeShellArg name} >&2
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
        printf 'expected Den capability fixture to fail: %s\n' ${lib.escapeShellArg name} >&2
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
        printf 'could not extract root Den capability diagnostic: %s\n' ${lib.escapeShellArg name} >&2
        head -c 4096 "$TMPDIR/${name}.stderr" >&2
        printf '\n' >&2
        exit 1
      fi

      ${checkExpectedFragments}
    ''
  ) failureCaseNames;
in
builtins.seq positiveResult (
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
)
