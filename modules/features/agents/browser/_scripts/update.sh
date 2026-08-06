#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

repository=vercel-labs/agent-browser
input_name=agent-browser-skill
module_path=modules/features/agents/browser/default.nix
pin_path=modules/features/agents/browser/_packages/agent-browser/pin.json
release_json=$(mktemp)
pin_tmp=$(mktemp "${pin_path}.tmp.XXXXXX")
trap 'rm -f -- "$release_json" "$pin_tmp"' EXIT

gh-api-get "repos/${repository}/releases/latest" >"$release_json"
tag=$(jq -er '.tag_name' "$release_json")
version=${tag#v}
if [[ $tag != v"$version" || ${#version} -gt 128 || ! $version =~ ^[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  printf 'agent-browser: unsupported release tag: %s\n' "$tag" >&2
  exit 1
fi
hashes='{}'

while IFS=$'\t' read -r system asset_name; do
  asset_url=$(jq -er --arg name "$asset_name" '
    [.assets[] | select(.name == $name and .state == "uploaded") | .browser_download_url]
    | if length == 1 then .[0] else error("release asset must be unique") end
  ' "$release_json")
  expected_url="https://github.com/${repository}/releases/download/${tag}/${asset_name}"
  [[ $asset_url == "$expected_url" ]] || {
    printf 'agent-browser: unexpected asset URL for %s\n' "$asset_name" >&2
    exit 1
  }
  hash=$(nix store prefetch-file --json "$asset_url" | jq -er .hash)
  hashes=$(jq -c --arg system "$system" --arg hash "$hash" \
    '.[$system] = $hash' <<<"$hashes")
done < <(jq -er '.assets | to_entries[] | [.key, .value.name] | @tsv' "$pin_path")

jq --argjson hashes "$hashes" '
  .assets |= with_entries(.value.hash = $hashes[.key])
' "$pin_path" >"$pin_tmp"
if ! cmp -s "$pin_tmp" "$pin_path"; then
  mv "$pin_tmp" "$pin_path"
fi

old_url=$(rg -o --no-filename "github:${repository}/v[^\"]+" "$module_path")
[[ $(rg -F -c "$old_url" "$module_path") == 1 ]] || {
  printf 'agent-browser: expected one authoritative input URL\n' >&2
  exit 1
}
OLD_URL=$old_url NEW_URL="github:${repository}/${tag}" \
  perl -0pi -e 's/\Q$ENV{OLD_URL}\E/$ENV{NEW_URL}/g' "$module_path"

nix run .#write-flake
nix flake update "$input_name"
