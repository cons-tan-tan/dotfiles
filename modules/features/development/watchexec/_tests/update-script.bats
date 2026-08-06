#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture WATCHEXEC_UPDATE_TEST_FIXTURE 'watchexec updater dependencies'
}

@test "watchexec updater derives asset names from the release version" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local stubs="$BATS_TEST_TMPDIR/stubs"
  local release_json="$BATS_TEST_TMPDIR/release.json"
  local pin=modules/features/development/watchexec/_overlays/pin.json
  local target=aarch64-apple-darwin
  local asset=watchexec-2.0.0-${target}.tar.xz
  mkdir -p "$repo/$(dirname "$pin")" "$stubs"
  git -C "$repo" init --quiet
  jq -n --arg target "$target" '
    {version: "1.0.0", assets: {"aarch64-darwin": {target: $target, hash: "sha256-old"}}}
  ' >"$repo/$pin"
  jq -n \
    --arg name "$asset" \
    --arg url "https://github.com/watchexec/watchexec/releases/download/v2.0.0/${asset}" '
    {tag_name: "v2.0.0", assets: [{name: $name, state: "uploaded", browser_download_url: $url}]}
  ' >"$release_json"

  write_bash_stub "$stubs/gh-api-get" <<'SH'
cat "$UPDATE_RELEASE_JSON"
SH
  write_bash_stub "$stubs/nix" <<'SH'
printf '{"hash":"sha256-new"}\n'
SH

  run env PATH="$stubs:$PATH" UPDATE_RELEASE_JSON="$release_json" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/development/watchexec/_scripts/update.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$repo/$pin")" = 2.0.0 ]
  [ "$(jq -r '.assets["aarch64-darwin"].hash' "$repo/$pin")" = sha256-new ]
}
