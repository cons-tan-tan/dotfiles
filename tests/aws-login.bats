#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/test-helper.bash"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/nix/packages/aws/aws-login.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  export PATH="$TEST_TMPDIR/bin:$PATH"
  mkdir -p "$TEST_TMPDIR/bin"
  printf '[profile test]\nregion = ap-northeast-1\n' >"$TEST_TMPDIR/base-config"

  write_bash_stub "$TEST_TMPDIR/bin/crudini" <<'SH'
printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/crudini-args"
cat >"$TEST_TMPDIR/merged-input"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_login() {
  run env \
    AWS_LOGIN_BASE_CONFIG="$TEST_TMPDIR/base-config" \
    AWS_CONFIG_FILE="$TEST_TMPDIR/config" \
    "$@" \
    bash -euo pipefail "$SCRIPT" --profile test
}

@test "merges the successful login candidate into the real config" {
  write_bash_stub "$TEST_TMPDIR/bin/aws" <<'SH'
printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/aws-args"
printf '%s\n' "$AWS_CONFIG_FILE" >"$TEST_TMPDIR/candidate-path"
printf '\nlogin_session = session-id\n' >>"$AWS_CONFIG_FILE"
SH

  run_login

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/aws-args")" = $'arg:login\narg:--profile\narg:test' ]
  [ "$(cat "$TEST_TMPDIR/crudini-args")" = $'arg:--merge\narg:'"$TEST_TMPDIR/config" ]
  grep -Fx "login_session = session-id" "$TEST_TMPDIR/merged-input"
  [ ! -e "$(cat "$TEST_TMPDIR/candidate-path")" ]
}

@test "does not merge when aws login fails" {
  write_bash_stub "$TEST_TMPDIR/bin/aws" <<'SH'
printf '%s\n' "$AWS_CONFIG_FILE" >"$TEST_TMPDIR/candidate-path"
exit 7
SH

  run_login

  [ "$status" -eq 7 ]
  [ ! -e "$TEST_TMPDIR/crudini-args" ]
  [ ! -e "$(cat "$TEST_TMPDIR/candidate-path")" ]
}
