#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
SCRIPT="$DOTFILES_TEST_REPO_ROOT/modules/features/agents/claude/_scripts/migrate-hooks-directory.sh"

setup() {
  TEST_ROOT="$(mktemp -d)"
  CLAUDE_HOME="$TEST_ROOT/home/.claude"
  DOTFILES_DIR="$TEST_ROOT/dotfiles"
  mkdir -p "$CLAUDE_HOME" "$DOTFILES_DIR/claude/hooks"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_migration() {
  run env \
    CLAUDE_HOME="$CLAUDE_HOME" \
    DOTFILES_DIR="$DOTFILES_DIR" \
    OLD_GEN_PATH="${OLD_GEN_PATH:-}" \
    bash "$SCRIPT"
}

@test "removes an absolute link to the legacy repository hooks directory" {
  ln -s "$DOTFILES_DIR/claude/hooks" "$CLAUDE_HOME/hooks"

  run_migration

  [ "$status" -eq 0 ]
  [ ! -L "$CLAUDE_HOME/hooks" ]
}

@test "removes a relative link to the legacy repository hooks directory" {
  local relative_target
  relative_target="$(realpath --relative-to="$CLAUDE_HOME" "$DOTFILES_DIR/claude/hooks")"
  ln -s "$relative_target" "$CLAUDE_HOME/hooks"

  run_migration

  [ "$status" -eq 0 ]
  [ ! -L "$CLAUDE_HOME/hooks" ]
}

@test "removes a dangling link inherited from the old Home Manager generation" {
  OLD_GEN_PATH="$TEST_ROOT/old-generation"
  mkdir -p "$OLD_GEN_PATH/home-files/.claude"
  ln -s "$TEST_ROOT/removed-store-hooks" "$OLD_GEN_PATH/home-files/.claude/hooks"
  ln -s "$OLD_GEN_PATH/home-files/.claude/hooks" "$CLAUDE_HOME/hooks"

  run_migration

  [ "$status" -eq 0 ]
  [ ! -L "$CLAUDE_HOME/hooks" ]
}

@test "preserves an unrelated hooks link" {
  mkdir -p "$TEST_ROOT/custom-hooks"
  ln -s "$TEST_ROOT/custom-hooks" "$CLAUDE_HOME/hooks"

  run_migration

  [ "$status" -eq 0 ]
  [ -L "$CLAUDE_HOME/hooks" ]
}

@test "preserves a real hooks directory" {
  mkdir "$CLAUDE_HOME/hooks"

  run_migration

  [ "$status" -eq 0 ]
  [ -d "$CLAUDE_HOME/hooks" ]
}
