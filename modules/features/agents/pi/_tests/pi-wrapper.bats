#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  SCRIPT="$REPO_ROOT/modules/features/agents/pi/_packages/pi/pi-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  write_bash_stub "$TEST_TMPDIR/pi" <<'SH'
printf 'package:%s\nskip:%s\ntelemetry:%s\n' \
  "$PI_PACKAGE_DIR" "$PI_SKIP_VERSION_CHECK" "$PI_TELEMETRY" >"$TEST_TMPDIR/result"
printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "sets managed Pi environment and forwards arguments" {
  run env \
    PI_BIN="$TEST_TMPDIR/pi" \
    PI_MANAGED_PACKAGE_DIR=/home/test/.pi/agent/package \
    bash -euo pipefail "$SCRIPT" --model test

  [ "$status" -eq 0 ]
  grep -Fx "package:/home/test/.pi/agent/package" "$TEST_TMPDIR/result"
  grep -Fx "skip:1" "$TEST_TMPDIR/result"
  grep -Fx "telemetry:0" "$TEST_TMPDIR/result"
  grep -Fx "arg:--model" "$TEST_TMPDIR/result"
  grep -Fx "arg:test" "$TEST_TMPDIR/result"
}

@test "Nix package pins the Pi child and managed package directory" {
  if [[ -z ${PI_WRAPPER_TEST_PACKAGE:-} ]]; then
    skip "PI_WRAPPER_TEST_PACKAGE is only available in the Nix check"
  fi

  run env TEST_TMPDIR="$TEST_TMPDIR" \
    "$PI_WRAPPER_TEST_PACKAGE/bin/pi" --model package-test

  [ "$status" -eq 0 ]
  grep -E '^package:/nix/store/.+-pi-managed-package-fixture$' "$TEST_TMPDIR/result"
  grep -Fx "skip:1" "$TEST_TMPDIR/result"
  grep -Fx "telemetry:0" "$TEST_TMPDIR/result"
  grep -Fx "arg:--model" "$TEST_TMPDIR/result"
  grep -Fx "arg:package-test" "$TEST_TMPDIR/result"
}
