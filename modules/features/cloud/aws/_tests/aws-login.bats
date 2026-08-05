#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_lib/bats/test-helper.bash"

setup() {
  require_nix_fixture AWS_LOGIN_TEST_PACKAGE "aws-login package"

  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
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

run_login() {
  run env \
    AWS_CONFIG_FILE="$TARGET" \
    AWS_LOGIN_TEST_MODE="${1:-success}" \
    "$AWS_LOGIN_TEST_PACKAGE/bin/aws-login" --profile test
}

@test "Nix-built aws-login preserves target-only settings and child argv" {
  printf '%s\n' \
    '[profile test]' \
    'credential_process = command' \
    '# keep' >"$TARGET"
  chmod 644 "$TARGET"

  run_login success

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/aws-args")" = $'login\n--profile\ntest' ]
  grep -Fx 'credential_process = command' "$TARGET"
  grep -Fx '# keep' "$TARGET"
  grep -Fx 'login_session = fixture-session' "$TARGET"
  [ "$(file_mode "$TARGET")" = 600 ]
}

@test "Nix-built aws-login preserves the target when the AWS child fails" {
  printf '%s\n' '[profile test]' 'credential_process = command' >"$TARGET"
  cp "$TARGET" "$TEST_TMPDIR/before"

  run_login fail

  [ "$status" -eq 7 ]
  cmp "$TEST_TMPDIR/before" "$TARGET"
}

@test "Nix-built aws-login rejects malformed targets before invoking AWS" {
  printf '%s\n' '[profile test]' 'malformed' >"$TARGET"
  cp "$TARGET" "$TEST_TMPDIR/before"

  run_login success

  [ "$status" -eq 1 ]
  cmp "$TEST_TMPDIR/before" "$TARGET"
  [ ! -e "$TEST_TMPDIR/aws-args" ]
}
