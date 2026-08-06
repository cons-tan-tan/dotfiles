#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup_file() {
  if [[ -z ${UPDATE_PINS_TEST_BIN:-} ]]; then
    return
  fi
  printf 'baseline\n' >"$DOTFILES_TEST_REPO_ROOT/managed-pin"
  git -C "$DOTFILES_TEST_REPO_ROOT" config commit.gpgSign false
  git -C "$DOTFILES_TEST_REPO_ROOT" config user.email update-pins-test@example.invalid
  git -C "$DOTFILES_TEST_REPO_ROOT" config user.name 'update-pins test'
  git -C "$DOTFILES_TEST_REPO_ROOT" add --all
  git -C "$DOTFILES_TEST_REPO_ROOT" commit --quiet -m 'update-pins baseline'
}

setup() {
  require_nix_fixture UPDATE_PINS_TEST_BIN 'packaged update-pins runner'
  UPDATE_PINS_TEST_LOG="$BATS_TEST_TMPDIR/update-pins.log"
  : >"$UPDATE_PINS_TEST_LOG"
  export UPDATE_PINS_TEST_LOG
}

@test "runner exposes package-owned targets and help" {
  run "$UPDATE_PINS_TEST_BIN" --list
  [ "$status" -eq 0 ]
  [ "$output" = $'alpha\tUpdate alpha fixture\nbeta\tUpdate beta fixture' ]

  run "$UPDATE_PINS_TEST_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Usage: update-pins"* ]]
}

@test "runner dispatches one target with its declared argv" {
  run "$UPDATE_PINS_TEST_BIN" alpha
  [ "$status" -eq 0 ]
  [ "$(<"$UPDATE_PINS_TEST_LOG")" = "alpha:fixed" ]

  run "$UPDATE_PINS_TEST_BIN" missing
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown target: missing"* ]]
  [ "$(<"$UPDATE_PINS_TEST_LOG")" = "alpha:fixed" ]
}

@test "runner updates every target in stable name order" {
  run "$UPDATE_PINS_TEST_BIN"
  [ "$status" -eq 0 ]
  [ "$(<"$UPDATE_PINS_TEST_LOG")" = $'alpha:fixed\nbeta:' ]
}

@test "check mode detects drift without changing the original worktree" {
  export UPDATE_PINS_TEST_TOUCH=alpha
  run "$UPDATE_PINS_TEST_BIN" --check alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"managed pins are out of date"* ]]
  [ "$(<"$DOTFILES_TEST_REPO_ROOT/managed-pin")" = baseline ]
  [ "$(<"$UPDATE_PINS_TEST_LOG")" = "alpha:fixed" ]
}

@test "normal mode applies changes only after every target succeeds" {
  export UPDATE_PINS_TEST_TOUCH=alpha
  run "$UPDATE_PINS_TEST_BIN" alpha
  [ "$status" -eq 0 ]
  [ "$(<"$DOTFILES_TEST_REPO_ROOT/managed-pin")" = changed ]
  git -C "$DOTFILES_TEST_REPO_ROOT" checkout -- managed-pin

  export UPDATE_PINS_TEST_FAIL=beta
  run "$UPDATE_PINS_TEST_BIN" alpha beta
  [ "$status" -eq 42 ]
  [ "$(<"$DOTFILES_TEST_REPO_ROOT/managed-pin")" = baseline ]
}
