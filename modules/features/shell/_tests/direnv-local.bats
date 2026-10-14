#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture DIRENV_LOCAL_TEST_BIN "standard direnv"
  require_nix_fixture DIRENVRC_TEST_FILE "global direnvrc"
  bats_require_minimum_version 1.5.0

  export DIRENV_CONFIG="$BATS_TEST_TMPDIR/config"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  export DIRENV_LOG_FORMAT='direnv: %s'
  export PATH="$(dirname "$DIRENV_LOCAL_TEST_BIN"):$PATH"
  unset DIRENV_DIR DIRENV_FILE DIRENV_DIFF DIRENV_WATCHES
  unset TEST_SHARED TEST_VALUE TEST_ORDER TEST_LOCAL TEST_ROOT TEST_COUNT

  project="$BATS_TEST_TMPDIR/project with spaces"
  mkdir -p "$DIRENV_CONFIG" "$project"
  cp "$DIRENVRC_TEST_FILE" "$DIRENV_CONFIG/direnvrc"
  cd "$project"
}

load_environment() {
  local changes
  changes=$("$DIRENV_LOCAL_TEST_BIN" export bash) || return
  eval "$changes"
}

@test "shared envrc remains usable without a local file" {
  printf 'export TEST_SHARED=shared\n' >.envrc
  "$DIRENV_LOCAL_TEST_BIN" allow

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -eq 0 ]
  jq -e '.TEST_SHARED == "shared"' <<<"$output"
}

@test "local overrides run after the tracked shared environment without editing it" {
  cat >.envrc <<'ENVRC'
export TEST_SHARED=shared
export TEST_VALUE=shared
export TEST_ORDER=shared
ENVRC
  cat >.envrc.local <<'ENVRC'
export TEST_VALUE=local
export TEST_LOCAL="$TEST_SHARED/local"
export TEST_ORDER="$TEST_ORDER:local"
ENVRC
  git init -q
  git add -f .envrc
  "$DIRENV_LOCAL_TEST_BIN" allow

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -eq 0 ]
  jq -e '.TEST_SHARED == "shared" and .TEST_VALUE == "local" and .TEST_LOCAL == "shared/local" and .TEST_ORDER == "shared:local"' <<<"$output"
  git diff --exit-code -- .envrc
}

@test "subdirectories use the local settings beside the discovered shared envrc" {
  printf 'export TEST_SHARED=shared\n' >.envrc
  printf 'export TEST_LOCAL=local\nexport TEST_ROOT="$PWD"\n' >.envrc.local
  mkdir child
  cd child
  printf 'export TEST_LOCAL=unexpected\n' >.envrc.local
  "$DIRENV_LOCAL_TEST_BIN" allow

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -eq 0 ]
  jq -e --arg root "$project" '.TEST_LOCAL == "local" and .TEST_ROOT == $root' <<<"$output"
}

@test "a local file alone does not activate standard direnv" {
  printf 'export TEST_LOCAL=local\n' >.envrc.local
  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "adding a local file is detected without reapproving the shared envrc" {
  printf 'export TEST_SHARED=shared\n' >.envrc
  "$DIRENV_LOCAL_TEST_BIN" allow
  load_environment
  printf 'export TEST_LOCAL=local\n' >.envrc.local

  load_environment
  [ "$TEST_SHARED" = shared ]
  [ "$TEST_LOCAL" = local ]
}

@test "editing local settings reloads them while preserving shared settings" {
  printf 'export TEST_SHARED=shared\n' >.envrc
  printf 'export TEST_VALUE=first\n' >.envrc.local
  "$DIRENV_LOCAL_TEST_BIN" allow
  load_environment
  printf 'export TEST_VALUE=second\n' >.envrc.local
  touch -t 202001010000 .envrc.local

  load_environment
  [ "$TEST_SHARED" = shared ]
  [ "$TEST_VALUE" = second ]
}

@test "updated shared variables are available to local settings after reapproval" {
  printf 'export TEST_SHARED=first\n' >.envrc
  printf 'export TEST_LOCAL="$TEST_SHARED/local"\n' >.envrc.local
  "$DIRENV_LOCAL_TEST_BIN" allow
  load_environment
  printf 'export TEST_SHARED=second\n' >.envrc
  touch -t 202001010000 .envrc

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"is blocked"* ]]
  "$DIRENV_LOCAL_TEST_BIN" allow
  load_environment
  [ "$TEST_SHARED" = second ]
  [ "$TEST_LOCAL" = second/local ]
}

@test "removing local overrides restores shared values and leaving unloads everything" {
  printf 'export TEST_SHARED=shared\nexport TEST_VALUE=shared\n' >.envrc
  "$DIRENV_LOCAL_TEST_BIN" allow
  load_environment
  printf 'export TEST_VALUE=local\nexport TEST_LOCAL=local\n' >.envrc.local
  load_environment
  [ "$TEST_VALUE" = local ]
  mv .envrc.local removed-local

  load_environment
  [ "$TEST_SHARED" = shared ]
  [ "$TEST_VALUE" = shared ]
  [ -z "${TEST_LOCAL+x}" ]

  cd "$BATS_TEST_TMPDIR"
  load_environment
  [ -z "${TEST_SHARED+x}" ]
  [ -z "${TEST_VALUE+x}" ]
}

@test "nested source_up preserves shared inheritance without adding an ancestor local override" {
  printf 'export TEST_SHARED=parent\n' >.envrc
  printf 'export TEST_LOCAL=parent\n' >.envrc.local
  mkdir child
  cd child
  printf 'source_up\nexport TEST_SHARED="$TEST_SHARED/child"\n' >.envrc
  printf 'export TEST_LOCAL="$TEST_SHARED/local"\n' >.envrc.local
  "$DIRENV_LOCAL_TEST_BIN" allow

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -eq 0 ]
  jq -e '.TEST_SHARED == "parent/child" and .TEST_LOCAL == "parent/child/local"' <<<"$output"
}

@test "projects that already source local settings do not execute them twice" {
  printf 'source_env_if_exists .envrc.local\nexport TEST_SHARED=after-local\n' >.envrc
  printf 'export TEST_COUNT=$(( ${TEST_COUNT:-0} + 1 ))\n' >.envrc.local
  "$DIRENV_LOCAL_TEST_BIN" allow

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -eq 0 ]
  jq -e '.TEST_COUNT == "1" and .TEST_SHARED == "after-local"' <<<"$output"
}

@test "shared failures under strict mode stop before loading local settings" {
  printf '[global]\nstrict_env = true\n' >"$DIRENV_CONFIG/direnv.toml"
  printf 'false\n' >.envrc
  printf 'export TEST_LOCAL=unexpected\n' >.envrc.local
  "$DIRENV_LOCAL_TEST_BIN" allow

  run --separate-stderr "$DIRENV_LOCAL_TEST_BIN" export json
  [ "$status" -ne 0 ]
  jq -e '.TEST_LOCAL == null' <<<"$output"
}
