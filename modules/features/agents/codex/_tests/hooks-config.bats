#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture CODEX_CONFIG_RECONCILE_TEST_PACKAGE "Codex config reconciliation"
  require_nix_fixture CODEX_HOOK_STATE_TEST_GENERATOR "Codex hook state generation"
  require_nix_fixture CODEX_HOOK_STATE_TEST_PAYLOAD "prebuilt Codex merge payload"
  TEST_TMPDIR=$(mktemp -d)
  export TMPDIR="$TEST_TMPDIR/scratch"
  mkdir -p "$TMPDIR" "$TEST_TMPDIR/user home/.codex"
  TARGET="$TEST_TMPDIR/user home/.codex/config.toml"
}

teardown() {
  rm -rf -- "$TEST_TMPDIR"
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

assert_cleaned_up() {
  local leftovers
  shopt -s nullglob
  leftovers=("${TARGET}.hooks-"* "$TMPDIR"/codex-hooks-*)
  [ "${#leftovers[@]}" -eq 0 ]
}

run_reconcile() {
  run "$CODEX_CONFIG_RECONCILE_TEST_PACKAGE/bin/codex-config-reconcile" "$TARGET" "$@"
}

@test "hook inspection ignores inherited homes and the caller's project" {
  mkdir -p "$TEST_TMPDIR/caller/.codex" "$TEST_TMPDIR/project/.codex"
  printf 'invalid TOML' > "$TEST_TMPDIR/caller/.codex/config.toml"
  printf 'invalid TOML' > "$TEST_TMPDIR/project/.codex/config.toml"
  cd "$TEST_TMPDIR/project"
  run env HOME="$TEST_TMPDIR/caller" \
    CODEX_HOME="$TEST_TMPDIR/caller/.codex" \
    XDG_CONFIG_HOME="$TEST_TMPDIR/caller/xdg" \
    "$CODEX_HOOK_STATE_TEST_GENERATOR/bin/codex-managed-hooks-state"

  [ "$status" -eq 0 ]
  jq -e '.hooks.state["/fixture/.codex/hooks.json:session_start:0:0"] ==
    {enabled: true, trusted_hash: "sha256:fixture"}' <<< "$output"
  [ "$(cat "$TEST_TMPDIR/caller/.codex/config.toml")" = 'invalid TOML' ]
  [ "$(cat "$TEST_TMPDIR/project/.codex/config.toml")" = 'invalid TOML' ]
  assert_cleaned_up
}

@test "runtime and prebuilt payloads preserve user settings and converge to identical config" {
  printf 'preserved = "user-owned"\n' > "$TARGET"
  chmod 640 "$TARGET"
  run_reconcile --state-generator "$CODEX_HOOK_STATE_TEST_GENERATOR/bin/codex-managed-hooks-state"
  [ "$status" -eq 0 ]
  [ "$(file_mode "$TARGET")" = 640 ]
  rg -F 'preserved = "user-owned"' "$TARGET"
  rg -F 'model = "managed"' "$TARGET"
  rg -F 'trusted_hash = "sha256:fixture"' "$TARGET"
  cp "$TARGET" "$TEST_TMPDIR/runtime.toml"

  run_reconcile --payload "$CODEX_HOOK_STATE_TEST_PAYLOAD"
  [ "$status" -eq 0 ]
  cmp "$TARGET" "$TEST_TMPDIR/runtime.toml"
  [ "$(file_mode "$TARGET")" = 640 ]
  assert_cleaned_up
}

@test "first activation writes a private config" {
  run_reconcile --state-generator "$CODEX_HOOK_STATE_TEST_GENERATOR/bin/codex-managed-hooks-state"
  [ "$status" -eq 0 ]
  [ "$(file_mode "$TARGET")" = 600 ]
  rg -F 'trusted_hash = "sha256:fixture"' "$TARGET"
  assert_cleaned_up
}

@test "hook inspection failure preserves the target and removes both temporary directories" {
  printf 'preserved = "before failure"\n' > "$TARGET"
  cp "$TARGET" "$TEST_TMPDIR/before.toml"
  CODEX_HOOKS_TEST_FAIL=1 run_reconcile --state-generator "$CODEX_HOOK_STATE_TEST_GENERATOR/bin/codex-managed-hooks-state"
  [ "$status" -eq 1 ]
  [[ $output == *'fixture hook inspection failure'* ]]
  cmp "$TARGET" "$TEST_TMPDIR/before.toml"
  assert_cleaned_up
}

@test "schema rejection leaves the original config intact" {
  printf 'preserved = 42\n' > "$TARGET"
  cp "$TARGET" "$TEST_TMPDIR/before.toml"
  run_reconcile --payload "$CODEX_HOOK_STATE_TEST_PAYLOAD"
  [ "$status" -ne 0 ]
  [[ $output == *'42 is not of type "string"'* ]]
  [[ $output == *'schema validation failed'* ]]
  cmp "$TARGET" "$TEST_TMPDIR/before.toml"
  assert_cleaned_up
}
