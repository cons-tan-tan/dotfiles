#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

repository=nulab/bee
input_name=bee-src
module_path=modules/features/agents/bee/default.nix
node_dir=modules/features/agents/bee/_packages/bee/node

metadata=$(nix store prefetch-file --json https://registry.npmjs.org/@nulab/bee/latest)
metadata_path=$(jq -er .storePath <<<"$metadata")
version=$(jq -er '.version' "$metadata_path")
if [[ ${#version} -gt 128 || ! $version =~ ^[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  printf 'bee: unsupported release version: %s\n' "$version" >&2
  exit 1
fi
old_url=$(rg -o --no-filename "github:${repository}/v[^\"]+" "$module_path")
[[ $(rg -F -c "$old_url" "$module_path") == 1 ]] || {
  printf 'bee: expected one authoritative input URL\n' >&2
  exit 1
}

npm install --prefix "$node_dir" --package-lock-only --ignore-scripts \
  --no-audit --no-fund --save-exact "@nulab/bee@${version}"
OLD_URL=$old_url NEW_URL="github:${repository}/v${version}" \
  perl -0pi -e 's/\Q$ENV{OLD_URL}\E/$ENV{NEW_URL}/g' "$module_path"

nix run .#write-flake
nix flake update "$input_name"
