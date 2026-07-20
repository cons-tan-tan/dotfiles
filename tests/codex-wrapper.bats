#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/test-helper.bash"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/codex/codex-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  write_bash_stub "$TEST_TMPDIR/codex" <<'SH'
printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/result"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_wrapper() {
  run env \
    CODEX_BIN="$TEST_TMPDIR/codex" \
    HERDR_SKILL_OVERRIDE='skills.config=[{path="/home/test/.codex/skills/herdr/SKILL.md",enabled=true}]' \
    "$@" \
    bash "$SCRIPT" user-arg
}

@test "passes arguments through without Herdr" {
  run_wrapper HERDR_ENV=0

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = "arg:user-arg" ]
}

@test "enables the Herdr skill inside Herdr" {
  run_wrapper HERDR_ENV=1

  [ "$status" -eq 0 ]
  grep -Fx "arg:-c" "$TEST_TMPDIR/result"
  grep -Fx 'arg:skills.config=[{path="/home/test/.codex/skills/herdr/SKILL.md",enabled=true}]' "$TEST_TMPDIR/result"
  grep -Fx "arg:user-arg" "$TEST_TMPDIR/result"
}
