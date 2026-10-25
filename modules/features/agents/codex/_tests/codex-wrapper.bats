#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  SCRIPT="$REPO_ROOT/modules/features/agents/codex/_packages/codex/codex-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  unset HERDR_ENV
  unset COMMIT_PROFILE_SELECTOR COMMIT_PROFILE_ARTIFACTS

  write_bash_stub "$TEST_TMPDIR/codex" <<'SH'
printf 'arg:%s\n' "$@" >"$TEST_TMPDIR/result"
exit "${CODEX_TEST_EXIT_STATUS:-0}"
SH
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

run_wrapper() {
  run env \
    CODEX_BIN="$TEST_TMPDIR/codex" \
    bash "$SCRIPT" "$@"
}

@test "explicitly uses embedded mode outside Herdr" {
  run_wrapper user-arg

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:--no-daemon\narg:user-arg' ]
}

@test "uses the same mode inside Herdr without skill config overrides" {
  HERDR_ENV=1 run_wrapper user-arg

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:--no-daemon\narg:user-arg' ]
}

@test "does not duplicate an explicit no-daemon flag" {
  run_wrapper resume --no-daemon user-arg

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:resume\narg:--no-daemon\narg:user-arg' ]
}

@test "does not mistake a prompt after the separator for a no-daemon flag" {
  run_wrapper -- --no-daemon

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:--no-daemon\narg:--\narg:--no-daemon' ]
}

@test "preserves config overrides and quoted arguments" {
  run_wrapper -c 'model="example"' 'prompt with spaces'

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:--no-daemon\narg:-c\narg:model="example"\narg:prompt with spaces' ]
}

@test "forwards the Codex exit status" {
  CODEX_TEST_EXIT_STATUS=42 run_wrapper user-arg

  [ "$status" -eq 42 ]
}

@test "adds a session override without duplicating embedded mode or modifying user arguments" {
  write_bash_stub "$TEST_TMPDIR/selector" <<'SH'
printf 'selector:%s\n' "$@" >"$TEST_TMPDIR/selection"
printf 'fine-grained\n'
SH
  mkdir -p "$TEST_TMPDIR/profiles/fine-grained"
  printf '%s' 'skills.config=[{path="/fine/SKILL.md",enabled=true}]' >"$TEST_TMPDIR/profiles/fine-grained/codex-override"
  export COMMIT_PROFILE_SELECTOR="$TEST_TMPDIR/selector" COMMIT_PROFILE_ARTIFACTS="$TEST_TMPDIR/profiles"
  run_wrapper --no-daemon -C '/repo with spaces' -c 'model="example"' -- 'prompt with spaces'
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:-c\narg:skills.config=[{path="/fine/SKILL.md",enabled=true}]\narg:--no-daemon\narg:-C\narg:/repo with spaces\narg:-c\narg:model="example"\narg:--\narg:prompt with spaces' ]
  [ "$(cat "$TEST_TMPDIR/selection")" = $'selector:--codex\nselector:--no-daemon\nselector:-C\nselector:/repo with spaces\nselector:-c\nselector:model="example"\nselector:--\nselector:prompt with spaces' ]
}

@test "packaged profile selection enables only the chosen commit path" {
  require_nix_fixture CODEX_PROFILED_TEST_PACKAGE "profile-aware Codex wrapper"
  export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  unset GHQ_ROOT
  git config --global ghq.root "$TEST_TMPDIR/root"
  mkdir -p "$TEST_TMPDIR/root/github.com/team/repo" "$TEST_TMPDIR/other"
  run "$CODEX_PROFILED_TEST_PACKAGE/bin/codex" -C "$TEST_TMPDIR/root/github.com/team/repo" prompt
  [ "$status" -eq 0 ]
  selected=$(rg '^arg:skills.config=' "$TEST_TMPDIR/result")
  [[ $selected == *'enabled=false},{path='*'enabled=true}]' ]]
  run "$CODEX_PROFILED_TEST_PACKAGE/bin/codex" -C "$TEST_TMPDIR/other" prompt
  [ "$status" -eq 0 ]
  selected=$(rg '^arg:skills.config=' "$TEST_TMPDIR/result")
  [[ $selected == *'enabled=true},{path='*'enabled=false}]' ]]
}

@test "Nix package pins the Codex child instead of using runtime overrides" {
  if [[ -z ${CODEX_WRAPPER_TEST_PACKAGE:-} ]]; then
    skip "CODEX_WRAPPER_TEST_PACKAGE is only available in the Nix check"
  fi

  run env TEST_TMPDIR="$TEST_TMPDIR" HERDR_ENV=1 CODEX_BIN=/missing/codex \
    "$CODEX_WRAPPER_TEST_PACKAGE/bin/codex" package-arg

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/result")" = $'arg:--no-daemon\narg:package-arg' ]
}
