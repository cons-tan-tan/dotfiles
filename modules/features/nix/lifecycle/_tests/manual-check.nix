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
  profileCleanupProbe = pkgs.writeShellApplication {
    name = "nh-clean-all";
    text = ''
      {
        printf 'profile'
        printf '\t%s' "$@"
        printf '\n'
      } >>"$NIX_STORE_CLEANUP_PROBE"
      exit "''${NIX_STORE_CLEANUP_PROFILE_STATUS:-0}"
    '';
  };
  fastNixGcProbe = pkgs.writeShellApplication {
    name = "fast-nix-gc";
    text = ''
      command -v nix >/dev/null
      {
        printf 'gc'
        printf '\t%s' "$@"
        printf '\n'
      } >>"$NIX_STORE_CLEANUP_PROBE"
      exit "''${NIX_STORE_CLEANUP_GC_STATUS:-0}"
    '';
  };
  storeCleanupContract = pkgs.callPackage ../_packages/store-cleanup {
    fastNixGc = fastNixGcProbe;
    fastNixGcArguments = cleanupPolicy.storeGc.arguments;
    nix = nhCleanNixProbe;
    profileCleanup = profileCleanupProbe;
  };
  argumentCheck = ciCheck.buildEntry (ciCheck.targets.both "package-smoke") (
    pkgs.runCommand "nh-clean-user-arguments" { } ''
      export NH_CLEAN_ARGUMENT_PROBE="$TMPDIR/called"

      PATH=/nonexistent \
        ${nhCleanUserArgumentContract}/bin/nh-clean-user --dry --no-gc

      test -f "$NH_CLEAN_ARGUMENT_PROBE"
      touch "$out"
    ''
  );
  smokeCheck = ciCheck.buildEntry (ciCheck.targets.linux "package-smoke") (
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
  storeCleanupCheck = ciCheck.buildEntry (ciCheck.targets.linux "package-smoke") (
    pkgs.runCommand "nix-store-cleanup-contract" { } ''
      export NIX_STORE_CLEANUP_PROBE="$TMPDIR/calls"
      readonly cleanup=${lib.escapeShellArg (lib.getExe storeCleanupContract)}
      readonly cmp=${lib.escapeShellArg (lib.getExe' pkgs.diffutils "cmp")}
      readonly expected="$TMPDIR/expected"

      PATH=/nonexistent "$cleanup"
      printf '%s\n' $'profile\t--no-gc' $'gc\t--no-vacuum' >"$expected"
      "$cmp" "$expected" "$NIX_STORE_CLEANUP_PROBE"

      : >"$NIX_STORE_CLEANUP_PROBE"
      if NIX_STORE_CLEANUP_PROFILE_STATUS=23 PATH=/nonexistent "$cleanup"; then
        echo "profile cleanup failure was ignored" >&2
        exit 1
      else
        status=$?
      fi
      test "$status" -eq 23
      printf '%s\n' $'profile\t--no-gc' >"$expected"
      "$cmp" "$expected" "$NIX_STORE_CLEANUP_PROBE"

      : >"$NIX_STORE_CLEANUP_PROBE"
      if NIX_STORE_CLEANUP_GC_STATUS=24 PATH=/nonexistent "$cleanup"; then
        echo "store GC failure was ignored" >&2
        exit 1
      else
        status=$?
      fi
      test "$status" -eq 24
      printf '%s\n' $'profile\t--no-gc' $'gc\t--no-vacuum' >"$expected"
      "$cmp" "$expected" "$NIX_STORE_CLEANUP_PROBE"

      : >"$NIX_STORE_CLEANUP_PROBE"
      if PATH=/nonexistent "$cleanup" unexpected; then
        echo "unexpected arguments were accepted" >&2
        exit 1
      else
        status=$?
      fi
      test "$status" -eq 2
      test ! -s "$NIX_STORE_CLEANUP_PROBE"

      touch "$out"
    ''
  );
in
{
  owner = "nh checks";
  artifacts = [ ];
  buildEntries = lib.listToAttrs (
    [ (lib.nameValuePair "nh-clean-user-arguments" argumentCheck) ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      (lib.nameValuePair "nh-clean-user-smoke" smokeCheck)
      (lib.nameValuePair "nix-store-cleanup-contract" storeCleanupCheck)
    ]
  );
}
