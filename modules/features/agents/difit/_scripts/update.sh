#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

repository=yoshiko-pg/difit
input_name=difit-src
module_path=modules/features/agents/difit/default.nix
pin_path=modules/features/agents/difit/_packages/difit/pin.json
package_set=modules/features/nixpkgs/_interface/nix-update-package-set.nix

metadata=$(nix store prefetch-file --json https://registry.npmjs.org/difit/latest)
metadata_path=$(jq -er .storePath <<<"$metadata")
version=$(jq -er '.version' "$metadata_path")
if [[ ${#version} -gt 128 || ! $version =~ ^[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  printf 'difit: unsupported release version: %s\n' "$version" >&2
  exit 1
fi
old_url=$(rg -o --no-filename "github:${repository}/v[^\"]+" "$module_path")
[[ $(rg -F -c "$old_url" "$module_path") == 1 ]] || {
  printf 'difit: expected one authoritative input URL\n' >&2
  exit 1
}
OLD_URL=$old_url NEW_URL="github:${repository}/v${version}" \
  perl -0pi -e 's/\Q$ENV{OLD_URL}\E/$ENV{NEW_URL}/g' "$module_path"

nix run .#write-flake
nix flake update "$input_name"
nix-update \
  --file "$package_set" \
  --version skip \
  --override-filename "$pin_path" \
  difit
