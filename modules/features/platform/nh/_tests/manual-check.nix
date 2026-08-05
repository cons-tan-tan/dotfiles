{
  ciCheck,
  lib,
  pkgs,
}:
let
  cleanupPolicy = import ../_data/cleanup-policy.nix;
  nhCleanUser = pkgs.callPackage ../_packages/clean-user { };
  nhCleanArgumentProbe = pkgs.writeShellApplication {
    name = "nh";
    text = ''
      expected=(
        ${lib.escapeShellArgs (
          [
            "clean"
            "user"
          ]
          ++ cleanupPolicy.arguments
          ++ [
            "--dry"
            "--no-gc"
          ]
        )}
      )
      actual=("$@")

      if (( ''${#actual[@]} != ''${#expected[@]} )); then
        printf 'unexpected argument count: %d\n' "$#" >&2
        printf 'actual: <%s>\n' "$@" >&2
        exit 1
      fi

      for index in "''${!expected[@]}"; do
        if [[ ''${actual[index]} != "''${expected[index]}" ]]; then
          printf 'argument %d: expected <%s>, got <%s>\n' \
            "$index" "''${expected[index]}" "''${actual[index]}" >&2
          exit 1
        fi
      done

      printf 'called\n' >"$NH_CLEAN_ARGUMENT_PROBE"
    '';
  };
  nhCleanNixProbe = pkgs.writeShellApplication {
    name = "nix";
    text = ''
      echo "nh-clean-user unexpectedly invoked the nix probe" >&2
      exit 1
    '';
  };
  nhCleanUserArgumentContract = pkgs.callPackage ../_packages/clean-user {
    nh = nhCleanArgumentProbe;
    nix = nhCleanNixProbe;
  };
  argumentCheck = ciCheck.annotate (ciCheck.targets.both "package-smoke") (
    pkgs.runCommand "nh-clean-user-arguments" { } ''
      export NH_CLEAN_ARGUMENT_PROBE="$TMPDIR/called"

      PATH=/nonexistent \
        ${nhCleanUserArgumentContract}/bin/nh-clean-user --dry --no-gc

      test -f "$NH_CLEAN_ARGUMENT_PROBE"
      touch "$out"
    ''
  );
  smokeCheck = ciCheck.annotate (ciCheck.targets.linux "package-smoke") (
    pkgs.runCommand "nh-clean-user-smoke" { } ''
      mkdir -p "$TMPDIR/home"

      # The timer never inherits an interactive shell. Deliberately make
      # PATH unusable and prove that the wrapper can still start nh and
      # nh's nix subprocess from its runtime closure.
      HOME="$TMPDIR/home" PATH=/nonexistent \
        ${nhCleanUser}/bin/nh-clean-user --dry --no-gc \
        >"$TMPDIR/output"

      ${lib.getExe pkgs.gnugrep} --fixed-strings \
        "Welcome to nh clean" "$TMPDIR/output" >/dev/null
      touch "$out"
    ''
  );
in
{
  owner = "nh checks";
  artifacts = [ ];
  checks = lib.listToAttrs (
    [ (lib.nameValuePair "nh-clean-user-arguments" argumentCheck) ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      (lib.nameValuePair "nh-clean-user-smoke" smokeCheck)
    ]
  );
}
