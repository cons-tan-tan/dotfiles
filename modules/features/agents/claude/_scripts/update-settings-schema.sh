#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

pin_path=modules/features/agents/claude/_pins/settings-schema.json
url=$(jq -er '.url | select(startswith("https://"))' "$pin_path")
hash=$(nix store prefetch-file --json "$url" | jq -er .hash)
pin_tmp=$(mktemp "${pin_path}.tmp.XXXXXX")
trap 'rm -f -- "$pin_tmp"' EXIT
jq --arg hash "$hash" '.hash = $hash' "$pin_path" >"$pin_tmp"
if ! cmp -s "$pin_tmp" "$pin_path"; then
  mv "$pin_tmp" "$pin_path"
fi
