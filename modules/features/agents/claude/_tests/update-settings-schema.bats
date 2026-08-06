#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture CLAUDE_UPDATE_TEST_FIXTURE 'Claude schema updater dependencies'
}

@test "Claude settings schema updater replaces only the fetched hash" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local stubs="$BATS_TEST_TMPDIR/stubs"
  local pin=modules/features/agents/claude/_pins/settings-schema.json
  mkdir -p "$repo/$(dirname "$pin")" "$stubs"
  git -C "$repo" init --quiet
  jq -n '{url: "https://example.invalid/schema.json", hash: "sha256-old"}' >"$repo/$pin"
  write_bash_stub "$stubs/nix" <<'SH'
printf '{"hash":"sha256-new"}\n'
SH

  run env PATH="$stubs:$PATH" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/claude/_scripts/update-settings-schema.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hash "$repo/$pin")" = sha256-new ]
  [ "$(jq -r .url "$repo/$pin")" = https://example.invalid/schema.json ]
}
