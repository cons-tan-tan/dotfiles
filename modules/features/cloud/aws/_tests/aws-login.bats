#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

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
    "$AWS_LOGIN_TEST_PACKAGE/bin/aws-login" --profile test
}

@test "Nix-built aws-login publishes a secure merged config" {
  printf '%s\n' \
    '[profile test]' \
    'credential_process = command' \
    '# keep' >"$TARGET"
  chmod 644 "$TARGET"

  run_login

  [ "$status" -eq 0 ]
  grep -Fx 'credential_process = command' "$TARGET"
  grep -Fx '# keep' "$TARGET"
  grep -Fx 'login_session = fixture-session' "$TARGET"
  [ "$(file_mode "$TARGET")" = 600 ]
}
