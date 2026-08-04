#!/usr/bin/env bats

setup() {
  load test-helper
  require_nix_fixture WINDOWS_COMPANION_DEPLOY_TEST_BIN "Windows companion deployment package"
  require_nix_fixture WINDOWS_COMPANION_DEPLOY_TEST_ROOT "isolated Windows home prefix"

  WORK="$BATS_TEST_TMPDIR/work"
  ROOT="$WINDOWS_COMPANION_DEPLOY_TEST_ROOT/test-user"
  SOURCE="$WORK/source"
  MANIFEST="$WORK/manifest.json"
  MV_STATE="$WORK/mv-state"
  RSYNC_STATE="$WORK/rsync-state"

  mkdir -p "$ROOT" "$SOURCE"
  export WINDOWS_COMPANION_DEPLOY_MV_STATE="$MV_STATE"
  export WINDOWS_COMPANION_DEPLOY_RSYNC_STATE="$RSYNC_STATE"
  unset WINDOWS_COMPANION_DEPLOY_MV_FAIL_AT
  unset WINDOWS_COMPANION_DEPLOY_MV_SIGNAL_BEFORE_AT
  unset WINDOWS_COMPANION_DEPLOY_MV_SIGNAL_AFTER_AT
  unset WINDOWS_COMPANION_DEPLOY_RSYNC_FAIL_AT
  unset WINDOWS_COMPANION_DEPLOY_RSYNC_SIGNAL_AFTER_AT
}

teardown() {
  chmod -R u+w "$WORK" "$WINDOWS_COMPANION_DEPLOY_TEST_ROOT" 2>/dev/null || true
  rm -rf "$WINDOWS_COMPANION_DEPLOY_TEST_ROOT"
}

write_manifest() {
  local files_json=${1:-'[]'}
  local trees_json=${2:-'[]'}
  jq -n \
    --arg root "$ROOT" \
    --argjson files "$files_json" \
    --argjson trees "$trees_json" \
    '{root: $root, directories: [".config/tool"], files: $files, trees: $trees}' \
    >"$MANIFEST"
}

assert_no_stages() {
  run find "$ROOT" -name '.deploy-file.*' -o -name '.*.new.*' -o -name '.*.backup.*'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "deploys files and trees on the first run and replaces them on repeat" {
  printf 'first\n' >"$SOURCE/settings"
  mkdir -p "$SOURCE/tree"
  printf 'keep-v1\n' >"$SOURCE/tree/keep"
  printf 'remove-me\n' >"$SOURCE/tree/remove"
  files=$(jq -nc --arg source "$SOURCE/settings" \
    '[{source: $source, destination: ".config/tool/settings", mode: "0600"}]')
  trees=$(jq -nc --arg source "$SOURCE/tree" \
    '[{source: $source, destination: ".local/share/tool", excludes: []}]')
  write_manifest "$files" "$trees"

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$ROOT/.config/tool/settings")" = first ]
  [ "$(stat -c '%a' "$ROOT/.config/tool/settings")" = 600 ]
  [ "$(cat "$ROOT/.local/share/tool/keep")" = keep-v1 ]

  printf 'second\n' >"$SOURCE/settings"
  printf 'keep-v2\n' >"$SOURCE/tree/keep"
  rm "$SOURCE/tree/remove"
  printf 'new\n' >"$SOURCE/tree/new"

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$ROOT/.config/tool/settings")" = second ]
  [ "$(cat "$ROOT/.local/share/tool/keep")" = keep-v2 ]
  [ "$(cat "$ROOT/.local/share/tool/new")" = new ]
  [ ! -e "$ROOT/.local/share/tool/remove" ]
  assert_no_stages
}

@test "normalizes read-only source trees for repeatable DrvFS cleanup" {
  mkdir -p "$ROOT/.local/share/tool" "$SOURCE/tree"
  printf 'obsolete\n' >"$ROOT/.local/share/tool/obsolete"
  printf 'immutable\n' >"$SOURCE/tree/keep"
  chmod -R a-w "$ROOT/.local/share/tool"
  chmod -R a-w "$SOURCE/tree"
  trees=$(jq -nc --arg source "$SOURCE/tree" \
    '[{source: $source, destination: ".local/share/tool", excludes: []}]')
  write_manifest '[]' "$trees"

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$(cat "$ROOT/.local/share/tool/keep")" = immutable ]
  [ ! -e "$ROOT/.local/share/tool/obsolete" ]
  [ "$(stat -c '%a' "$ROOT/.local/share/tool")" = 755 ]
  [ "$(stat -c '%a' "$ROOT/.local/share/tool/keep")" = 644 ]
  assert_no_stages
}

@test "keeps the existing tree and removes staging data when rsync fails" {
  mkdir -p "$ROOT/.local/share/tool"
  printf 'existing\n' >"$ROOT/.local/share/tool/keep"
  trees=$(jq -nc --arg source "$SOURCE/missing" \
    '[{source: $source, destination: ".local/share/tool", excludes: []}]')
  write_manifest '[]' "$trees"

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [ "$(cat "$ROOT/.local/share/tool/keep")" = existing ]
  assert_no_stages
}

@test "restores the existing tree when publication fails" {
  mkdir -p "$ROOT/.local/share/tool" "$SOURCE/tree"
  printf 'existing\n' >"$ROOT/.local/share/tool/keep"
  printf 'replacement\n' >"$SOURCE/tree/keep"
  trees=$(jq -nc --arg source "$SOURCE/tree" \
    '[{source: $source, destination: ".local/share/tool", excludes: []}]')
  write_manifest '[]' "$trees"
  export WINDOWS_COMPANION_DEPLOY_RSYNC_FAIL_AT=3

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -eq 1 ]
  [ "$(cat "$ROOT/.local/share/tool/keep")" = existing ]
  assert_no_stages
}

@test "restores the existing tree when interrupted immediately after publication" {
  mkdir -p "$ROOT/.local/share/tool" "$SOURCE/tree"
  printf 'existing\n' >"$ROOT/.local/share/tool/keep"
  printf 'replacement\n' >"$SOURCE/tree/keep"
  trees=$(jq -nc --arg source "$SOURCE/tree" \
    '[{source: $source, destination: ".local/share/tool", excludes: []}]')
  write_manifest '[]' "$trees"
  export WINDOWS_COMPANION_DEPLOY_RSYNC_SIGNAL_AFTER_AT=3

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -eq 143 ]
  [ "$(cat "$ROOT/.local/share/tool/keep")" = existing ]
  assert_no_stages
}

@test "removes a staged file when install fails" {
  files=$(jq -nc --arg source "$SOURCE/missing" \
    '[{source: $source, destination: ".config/tool/settings", mode: "0644"}]')
  write_manifest "$files" '[]'

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [ ! -e "$ROOT/.config/tool/settings" ]
  assert_no_stages
}

@test "rejects roots outside the configured users directory" {
  ROOT="$WORK/outside/test-user"
  mkdir -p "$ROOT"
  write_manifest

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be one user below"* ]]
}

@test "rejects traversal and symlink destination components" {
  files=$(jq -nc --arg source "$SOURCE/missing" \
    '[{source: $source, destination: "../outside", mode: "0644"}]')
  write_manifest "$files" '[]'

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe relative path"* ]]

  mkdir -p "$WORK/outside"
  rm -rf "$ROOT/.config"
  ln -s "$WORK/outside" "$ROOT/.config"
  files=$(jq -nc --arg source "$SOURCE/missing" \
    '[{source: $source, destination: ".config/settings", mode: "0644"}]')
  write_manifest "$files" '[]'

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"traverses a symlink"* ]]
  [ ! -e "$WORK/outside/settings" ]
}

@test "rejects tree destinations with a trailing slash" {
  mkdir -p "$SOURCE/tree"
  trees=$(jq -nc --arg source "$SOURCE/tree" \
    '[{source: $source, destination: "unsafe/", excludes: []}]')
  write_manifest '[]' "$trees"

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe relative path"* ]]
  assert_no_stages
}

@test "rejects a Windows home reached through a symlinked parent" {
  local actual_prefix="$WORK/actual/Users"
  local linked_prefix="$WINDOWS_COMPANION_DEPLOY_TEST_ROOT"
  mkdir -p "$actual_prefix/test-user" "$(dirname "$linked_prefix")"
  rm -rf "$linked_prefix"
  ln -s "$actual_prefix" "$linked_prefix"
  ROOT="$linked_prefix/test-user"
  write_manifest

  run "$WINDOWS_COMPANION_DEPLOY_TEST_BIN" "$MANIFEST"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe or missing Windows home"* ]]
}
