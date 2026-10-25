#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  unset GHQ_ROOT GIT_DIR GIT_WORK_TREE
  GHQ_TEST_ROOT="$TEST_TMPDIR/ghq root"
  git config --global ghq.root "$GHQ_TEST_ROOT"
  TARGET="$GHQ_TEST_ROOT/github.com/team/project"
  OTHER="$GHQ_TEST_ROOT/github.com/another/project"
  mkdir -p "$TARGET/src" "$OTHER"
  SELECTOR=${COMMIT_PROFILE_TEST_SELECTOR:-$TEST_TMPDIR/selector}
  if [[ -z ${COMMIT_PROFILE_TEST_SELECTOR:-} ]]; then
    export COMMIT_PROFILE_TEST_SOURCE="$DOTFILES_TEST_REPO_ROOT/modules/features/agents/skills/_packages/commit-profiles/select-profile.sh"
    write_bash_stub "$SELECTOR" <<'SH'
set -euo pipefail
PROFILE_SCOPES=(github.com/team)
source "$COMMIT_PROFILE_TEST_SOURCE"
SH
  fi
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "matches a scope, its checkout and subdirectories" {
  for directory in "$GHQ_TEST_ROOT/github.com/team" "$TARGET" "$TARGET/src"; do
    run "$SELECTOR" --cwd "$directory"
    [ "$status" -eq 0 ]
    [ "$output" = fine-grained ]
  done
}

@test "keeps unrelated hosts, prefix lookalikes and non-ghq paths standard" {
  for directory in "$OTHER" "$GHQ_TEST_ROOT/github.com/team-extra/project" "$GHQ_TEST_ROOT/gitlab.com/team/project" "$TEST_TMPDIR/github.com/team/project"; do
    mkdir -p "$directory"
    run "$SELECTOR" --cwd "$directory"
    [ "$status" -eq 0 ]
    [ "$output" = standard ]
  done
}

@test "resolves directory symlinks and multiple ghq roots" {
  ln -s "$TARGET" "$TEST_TMPDIR/linked"
  run "$SELECTOR" --cwd "$TEST_TMPDIR/linked/src"
  [ "$status" -eq 0 ]
  [ "$output" = fine-grained ]

  git config --global --add ghq.root "$TEST_TMPDIR/second root"
  mkdir -p "$TEST_TMPDIR/second root/github.com/team/repo"
  run "$SELECTOR" --cwd "$TEST_TMPDIR/second root/github.com/team/repo"
  [ "$status" -eq 0 ]
  [ "$output" = fine-grained ]
}

@test "inherits the main checkout scope in an external linked worktree" {
  git -C "$TARGET" init -q
  git -C "$TARGET" -c user.name=Test -c user.email=test@example.com commit -qm initial --allow-empty
  git -C "$TARGET" worktree add -qb test "$TEST_TMPDIR/external worktree"
  mkdir -p "$TEST_TMPDIR/external worktree/src"
  run "$SELECTOR" --cwd "$TEST_TMPDIR/external worktree/src"
  [ "$status" -eq 0 ]
  [ "$output" = fine-grained ]
}

@test "uses Codex directory options while preserving option values and prompt separators" {
  cd "$OTHER"
  for flag in -C --cd; do
    run "$SELECTOR" --codex exec "$flag" "$TARGET/src" -c 'model="example"' 'prompt with spaces'
    [ "$status" -eq 0 ]
    [ "$output" = fine-grained ]
  done
  run "$SELECTOR" --codex "--cd=$TARGET" -- --cd "$OTHER"
  [ "$status" -eq 0 ]
  [ "$output" = fine-grained ]
  run "$SELECTOR" --codex "-C$TARGET" -C "$OTHER"
  [ "$status" -eq 0 ]
  [ "$output" = standard ]
  run "$SELECTOR" --codex -c -C -- --cd "$TARGET"
  [ "$status" -eq 0 ]
  [ "$output" = standard ]
}

@test "resolves relative Codex directories from the invocation directory" {
  cd "$TARGET"
  run "$SELECTOR" --codex -C ../project/src
  [ "$status" -eq 0 ]
  [ "$output" = fine-grained ]
  mkdir -p "$TEST_TMPDIR/elsewhere/src"
  export CDPATH="$TEST_TMPDIR/elsewhere"
  run "$SELECTOR" --codex -C src
  [ "$status" -eq 0 ]
  [ "$output" = fine-grained ]
}

@test "reports missing and invalid directory arguments" {
  run "$SELECTOR" --codex --cd
  [ "$status" -eq 2 ]
  [[ $output == *'missing directory for --cd'* ]]
  run "$SELECTOR" --cwd "$TEST_TMPDIR/missing"
  [ "$status" -ne 0 ]
  [[ $output == *missing* ]]
}

@test "parallel selection leaves configuration unchanged" {
  cp "$GIT_CONFIG_GLOBAL" "$TEST_TMPDIR/config.before"
  "$SELECTOR" --cwd "$TARGET" > "$TEST_TMPDIR/target.result" &
  target_pid=$!
  "$SELECTOR" --cwd "$OTHER" > "$TEST_TMPDIR/other.result" &
  other_pid=$!
  wait "$target_pid"
  wait "$other_pid"
  [ "$(cat "$TEST_TMPDIR/target.result")" = fine-grained ]
  [ "$(cat "$TEST_TMPDIR/other.result")" = standard ]
  cmp "$GIT_CONFIG_GLOBAL" "$TEST_TMPDIR/config.before"
}
