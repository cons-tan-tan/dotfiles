#!/usr/bin/env bats

source "$BATS_TEST_DIRNAME/test-helper.bash"

setup() {
  require_nix_fixture AWS_CONFIG_RECONCILE_TEST_PACKAGE "aws-config-reconcile package"

  TEST_TMPDIR="$(mktemp -d)"
  HOME="$TEST_TMPDIR/home"
  export HOME
  mkdir -m 700 -p "$HOME/.aws"
  TARGET="$HOME/.aws/config"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

file_inode() {
  stat -c %i "$1" 2>/dev/null || stat -f %i "$1"
}

run_reconcile() {
  run "$AWS_CONFIG_RECONCILE_TEST_PACKAGE/bin/aws-config-reconcile"
}

@test "activation adapter restores managed sessions and removes undeclared profiles" {
  printf '%s\n' \
    '[profile test]' \
    'region = user-change' \
    'login_session = fixture-session' \
    '' \
    '[profile unknown]' \
    'login_session = remove' >"$TARGET"

  run_reconcile

  [ "$status" -eq 0 ]
  grep -Fx 'region = baseline' "$TARGET"
  grep -Fx 'credential_process = command' "$TARGET"
  grep -Fx 'login_session = fixture-session' "$TARGET"
  ! grep -F 'unknown' "$TARGET"
  [ "$(file_mode "$TARGET")" = 600 ]
}

@test "activation adapter is idempotent and leaves malformed targets unchanged" {
  printf '%s\n' \
    '[profile test]' \
    'region = baseline' \
    'credential_process = command' \
    'login_session = fixture-session' >"$TARGET"

  run_reconcile
  [ "$status" -eq 0 ]
  inode="$(file_inode "$TARGET")"
  run_reconcile
  [ "$status" -eq 0 ]
  [ "$(file_inode "$TARGET")" = "$inode" ]

  printf '%s\n' '[profile test]' 'malformed' >"$TARGET"
  cp "$TARGET" "$TEST_TMPDIR/before"
  run_reconcile
  [ "$status" -eq 1 ]
  cmp "$TEST_TMPDIR/before" "$TARGET"
}
