#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture HERDR_UPDATE_TEST_FIXTURE 'Herdr updater dependencies'
}

@test "herdr updater synchronizes release assets and source hash" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local stubs="$BATS_TEST_TMPDIR/stubs"
  local release_json="$BATS_TEST_TMPDIR/release.json"
  local pin=modules/features/agents/herdr/_packages/herdr/pin.json
  local asset=herdr-linux-x86_64
  mkdir -p "$repo/$(dirname "$pin")" "$stubs"
  git -C "$repo" init --quiet
  jq -n --arg name "$asset" '
    {version: "1.0.0", srcHash: "sha256-old-source", assets: {"x86_64-linux": {name: $name, hash: "sha256-old"}}}
  ' >"$repo/$pin"
  jq -n \
    --arg name "$asset" \
    --arg url "https://github.com/ogulcancelik/herdr/releases/download/v2.0.0/${asset}" '
    {tag_name: "v2.0.0", assets: [{name: $name, state: "uploaded", browser_download_url: $url}]}
  ' >"$release_json"

  write_bash_stub "$stubs/gh-api-get" <<'SH'
cat "$UPDATE_RELEASE_JSON"
SH
write_bash_stub "$stubs/nix" <<'SH'
url=${!#}
if [[ $url == *'/archive/refs/tags/'* ]]; then
  printf '{"hash":"sha256-new-source"}\n'
else
  printf '{"hash":"sha256-new-asset"}\n'
fi
SH

  run env PATH="$stubs:$PATH" UPDATE_RELEASE_JSON="$release_json" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/herdr/_scripts/update.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$repo/$pin")" = 2.0.0 ]
  [ "$(jq -r .srcHash "$repo/$pin")" = sha256-new-source ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$repo/$pin")" = sha256-new-asset ]
}
