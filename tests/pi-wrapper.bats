#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/pi/pi-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  cat >"$TEST_TMPDIR/pi" <<'SH'
#!/usr/bin/env bash
printf 'package:%s\nskip:%s\ntelemetry:%s\n' \
  "$PI_PACKAGE_DIR" "$PI_SKIP_VERSION_CHECK" "$PI_TELEMETRY" >"$TEST_TMPDIR/result"
printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
SH
  chmod +x "$TEST_TMPDIR/pi"
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
