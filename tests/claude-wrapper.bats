#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/claude-code/claude-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  cat >"$TEST_TMPDIR/claude" <<'SH'
#!/usr/bin/env bash
printf 'path:%s\n' "$PATH" >"$TEST_TMPDIR/result"
printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
SH
  chmod +x "$TEST_TMPDIR/claude"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_wrapper() {
  run env \
    CLAUDE_BASE="$TEST_TMPDIR/claude" \
    NODE_BIN=/nix/store/node/bin \
    HERDR_PLUGIN=/nix/store/herdr-plugin \
    "$@" \
    bash "$SCRIPT" user-arg
}

@test "runs Claude with the default effort without Herdr" {
  run_wrapper HERDR_ENV=0

  [ "$status" -eq 0 ]
  grep -F "path:/nix/store/node/bin:" "$TEST_TMPDIR/result"
  [ "$(grep -c '^arg:' "$TEST_TMPDIR/result")" -eq 3 ]
  grep -Fx "arg:--effort" "$TEST_TMPDIR/result"
  grep -Fx "arg:xhigh" "$TEST_TMPDIR/result"
  grep -Fx "arg:user-arg" "$TEST_TMPDIR/result"
}

@test "adds the Herdr plugin only inside Herdr" {
  run_wrapper HERDR_ENV=1

  [ "$status" -eq 0 ]
  grep -Fx "arg:--plugin-dir" "$TEST_TMPDIR/result"
  grep -Fx "arg:/nix/store/herdr-plugin" "$TEST_TMPDIR/result"
}
