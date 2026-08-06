#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

pin_path=modules/features/agents/base/_packages/shellfirm/pin.json
package_lock=modules/features/agents/base/_packages/shellfirm/Cargo.lock
guard_manifest=modules/features/agents/base/_packages/command-guard/Cargo.toml
package_set=modules/features/nixpkgs/_interface/nix-update-package-set.nix

tag=$(gh-api-get repos/kaplanelad/shellfirm/releases/latest | jq -er '.tag_name')
version=${tag#v}
if [[ $tag != v"$version" || ${#version} -gt 128 || ! $version =~ ^[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
  printf 'shellfirm: unsupported release tag: %s\n' "$tag" >&2
  exit 1
fi
source_url="https://github.com/kaplanelad/shellfirm/archive/refs/tags/v${version}.tar.gz"
source_metadata=$(nix store prefetch-file --unpack --json "$source_url")
source_path=$(jq -er .storePath <<<"$source_metadata")
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/shellfirm-update.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
cp -R "$source_path" "$work_dir/source"
chmod -R u+w "$work_dir/source"
cp "$package_lock" "$work_dir/source/Cargo.lock"
cargo update --manifest-path "$work_dir/source/Cargo.toml"
cp "$work_dir/source/Cargo.lock" "$package_lock"

# nix-update builds the candidate package, so its repository-owned lockfile
# must already match the candidate release before that build starts.
nix-update \
  --file "$package_set" \
  --version "$version" \
  --override-filename "$pin_path" \
  shellfirm

[[ $(rg -c '^shellfirm = \{ version = "=[^"]+", default-features = false \}$' "$guard_manifest") == 1 ]] || {
  printf 'shellfirm: expected one exact command-guard dependency\n' >&2
  exit 1
}
SHELLFIRM_VERSION=$version perl -0pi -e '
  s{^(shellfirm = \{ version = ")=[^"]+(".*)$}{$1=$ENV{SHELLFIRM_VERSION}$2}m
' "$guard_manifest"
cargo update \
  --manifest-path "$guard_manifest" \
  --package shellfirm \
  --precise "$version"
