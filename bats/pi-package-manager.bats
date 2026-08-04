#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/test-helper.bash"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/pi/package-manager.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR

  write_bash_stub "$TEST_TMPDIR/pnpm" <<'SH'
env | sort >"$TEST_TMPDIR/env"
printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/args"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "isolates pnpm state and forwards arguments" {
  expected_path="/nix/store/node/bin:$TEST_TMPDIR/pi-npm/pnpm-home:$PATH"

  run env \
    HOME="$TEST_TMPDIR/home" \
    PI_NPM_HOME="$TEST_TMPDIR/pi-npm" \
    NODE_BIN=/nix/store/node/bin \
    PNPM_BIN="$TEST_TMPDIR/pnpm" \
    bash -euo pipefail "$SCRIPT" install package-name

  [ "$status" -eq 0 ]
  grep -Fx "PNPM_HOME=$TEST_TMPDIR/pi-npm/pnpm-home" "$TEST_TMPDIR/env"
  grep -Fx "XDG_CACHE_HOME=$TEST_TMPDIR/pi-npm/cache" "$TEST_TMPDIR/env"
  grep -Fx "XDG_DATA_HOME=$TEST_TMPDIR/pi-npm/data" "$TEST_TMPDIR/env"
  grep -Fx "XDG_STATE_HOME=$TEST_TMPDIR/pi-npm/state" "$TEST_TMPDIR/env"
  grep -Fx "NPM_CONFIG_USERCONFIG=$TEST_TMPDIR/pi-npm/npmrc" "$TEST_TMPDIR/env"
  grep -Fx "NPM_CONFIG_GLOBALCONFIG=$TEST_TMPDIR/pi-npm/global-npmrc" "$TEST_TMPDIR/env"
  grep -Fx "NPM_CONFIG_FUND=false" "$TEST_TMPDIR/env"
  grep -Fx "NPM_CONFIG_AUDIT=false" "$TEST_TMPDIR/env"
  grep -Fx "PATH=$expected_path" "$TEST_TMPDIR/env"
  [ -f "$TEST_TMPDIR/pi-npm/npmrc" ]
  [ -f "$TEST_TMPDIR/pi-npm/global-npmrc" ]
  [ "$(cat "$TEST_TMPDIR/args")" = $'arg:install\narg:package-name' ]
}

@test "uses a Pi-specific package-manager home by default" {
  run env -u PI_NPM_HOME \
    HOME="$TEST_TMPDIR/home" \
    NODE_BIN=/nix/store/node/bin \
    PNPM_BIN="$TEST_TMPDIR/pnpm" \
    bash -euo pipefail "$SCRIPT" install

  [ "$status" -eq 0 ]
  grep -Fx "PNPM_HOME=$TEST_TMPDIR/home/.pi/npm-env/pnpm-home" "$TEST_TMPDIR/env"
  [ -f "$TEST_TMPDIR/home/.pi/npm-env/npmrc" ]
  [ -f "$TEST_TMPDIR/home/.pi/npm-env/global-npmrc" ]
}
