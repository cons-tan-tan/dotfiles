#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture SHELLFIRM_UPDATE_TEST_FIXTURE 'shellfirm updater dependencies'
}

@test "shellfirm updater prepares the candidate lock before nix-update builds it" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local stubs="$BATS_TEST_TMPDIR/stubs"
  local source="$BATS_TEST_TMPDIR/upstream"
  local calls="$BATS_TEST_TMPDIR/calls"
  local package_dir=modules/features/agents/base/_packages/shellfirm
  local guard_dir=modules/features/agents/base/_packages/command-guard
  mkdir -p "$repo/$package_dir" "$repo/$guard_dir" "$stubs" "$source"
  git -C "$repo" init --quiet
  printf '[package]\nname = "shellfirm"\nversion = "2.0.0"\n' >"$source/Cargo.toml"
  printf 'old package lock\n' >"$repo/$package_dir/Cargo.lock"
  printf '{}\n' >"$repo/$package_dir/pin.json"
  printf '[dependencies]\nshellfirm = { version = "=1.0.0", default-features = false }\n' \
    >"$repo/$guard_dir/Cargo.toml"
  printf 'old guard lock\n' >"$repo/$guard_dir/Cargo.lock"

  write_bash_stub "$stubs/gh-api-get" <<'SH'
printf '{"tag_name":"v2.0.0"}\n'
SH
  write_bash_stub "$stubs/nix" <<'SH'
jq -n --arg storePath "$UPDATE_SOURCE" '{storePath: $storePath}'
SH
  write_bash_stub "$stubs/cargo" <<'SH'
printf 'cargo' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
manifest=
while (($# > 0)); do
  if [[ $1 == --manifest-path ]]; then
    manifest=$2
    break
  fi
  shift
done
if [[ $manifest == */source/Cargo.toml ]]; then
  printf 'candidate package lock\n' >"${manifest%/*}/Cargo.lock"
else
  printf 'updated guard lock\n' >"${manifest%/*}/Cargo.lock"
fi
SH
  write_bash_stub "$stubs/nix-update" <<'SH'
printf 'nix-update' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
SH

  run env \
    PATH="$stubs:$PATH" \
    UPDATE_CALLS="$calls" \
    UPDATE_SOURCE="$source" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/base/_scripts/update-shellfirm.sh"
  [ "$status" -eq 0 ]
  [ "$(<"$repo/$package_dir/Cargo.lock")" = 'candidate package lock' ]
  rg -F 'shellfirm = { version = "=2.0.0", default-features = false }' \
    "$repo/$guard_dir/Cargo.toml"
  [ "$(<"$repo/$guard_dir/Cargo.lock")" = 'updated guard lock' ]
  [[ "$(sed -n '1p' "$calls")" == cargo* ]]
  [[ "$(sed -n '2p' "$calls")" == *'<--version> <2.0.0>'* ]]
  [[ "$(sed -n '2p' "$calls")" == nix-update* ]]
  [[ "$(sed -n '3p' "$calls")" == cargo* ]]
}
