#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  REPO_ROOT="$DOTFILES_TEST_REPO_ROOT"
  SCRIPT="$REPO_ROOT/modules/features/agents/claude/_packages/claude-code/claude-wrapper.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  unset COMMIT_PROFILE_SELECTOR COMMIT_PROFILE_ARTIFACTS

  write_bash_stub "$TEST_TMPDIR/claude" <<'SH'
printf 'path:%s\n' "$PATH" >"$TEST_TMPDIR/result"
printf 'arg:%s\n' "$@" >>"$TEST_TMPDIR/result"
SH
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

@test "loads one commit directory alongside the Herdr plugin" {
  write_bash_stub "$TEST_TMPDIR/selector" <<'SH'
printf 'selector:%s\n' "$@" >"$TEST_TMPDIR/selection"
printf 'fine-grained\n'
SH
  export COMMIT_PROFILE_SELECTOR="$TEST_TMPDIR/selector" COMMIT_PROFILE_ARTIFACTS='/profiles with spaces'
  run_wrapper HERDR_ENV=1
  [ "$status" -eq 0 ]
  [ "$(rg '^arg:' "$TEST_TMPDIR/result")" = $'arg:--effort\narg:xhigh\narg:--add-dir\narg:/profiles with spaces/fine-grained\narg:--plugin-dir\narg:/nix/store/herdr-plugin\narg:user-arg' ]
  [ "$(cat "$TEST_TMPDIR/selection")" = "$(printf 'selector:--cwd\nselector:%s' "$PWD")" ]
}

@test "packaged Claude wrapper chooses a single directory with an unqualified commit skill" {
  require_nix_fixture CLAUDE_PROFILED_TEST_PACKAGE "profile-aware Claude wrapper"
  export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
  unset GHQ_ROOT
  git config --global ghq.root "$TEST_TMPDIR/root"
  mkdir -p "$TEST_TMPDIR/root/github.com/team/repo" "$TEST_TMPDIR/other"
  cd "$TEST_TMPDIR/root/github.com/team/repo"
  run "$CLAUDE_PROFILED_TEST_PACKAGE/bin/claude" prompt
  [ "$status" -eq 0 ]
  skill_root=$(rg '^arg:.*/fine-grained$' "$TEST_TMPDIR/result")
  [ -f "${skill_root#arg:}/.claude/skills/commit/SKILL.md" ]
  cd "$TEST_TMPDIR/other"
  run "$CLAUDE_PROFILED_TEST_PACKAGE/bin/claude" prompt
  [ "$status" -eq 0 ]
  skill_root=$(rg '^arg:.*/standard$' "$TEST_TMPDIR/result")
  [ -f "${skill_root#arg:}/.claude/skills/commit/SKILL.md" ]
}

@test "Nix package pins the Claude child Node path and Herdr plugin" {
  if [[ -z ${CLAUDE_WRAPPER_TEST_PACKAGE:-} ]]; then
    skip "CLAUDE_WRAPPER_TEST_PACKAGE is only available in the Nix check"
  fi

  run env TEST_TMPDIR="$TEST_TMPDIR" HERDR_ENV=1 \
    "$CLAUDE_WRAPPER_TEST_PACKAGE/bin/claude" package-arg

  [ "$status" -eq 0 ]
  grep -E '^path:/nix/store/.+-nodejs-.+/bin:' "$TEST_TMPDIR/result"
  grep -Fx "arg:--effort" "$TEST_TMPDIR/result"
  grep -Fx "arg:xhigh" "$TEST_TMPDIR/result"
  grep -Fx "arg:--plugin-dir" "$TEST_TMPDIR/result"
  grep -E '^arg:/nix/store/.+-herdr-plugin-fixture$' "$TEST_TMPDIR/result"
  grep -Fx "arg:package-arg" "$TEST_TMPDIR/result"

}
