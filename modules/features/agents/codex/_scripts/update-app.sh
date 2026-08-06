#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

pin_path=modules/features/agents/codex/_packages/codex-app/pin.json
appcast=$(jq -er '.appcast | select(startswith("https://"))' "$pin_path")
appcast_metadata=$(nix store prefetch-file --json "$appcast")
appcast_path=$(jq -er .storePath <<<"$appcast_metadata")
xpath='//item[(not(sparkle:hardwareRequirements) or normalize-space(sparkle:hardwareRequirements)="arm64") and enclosure[contains(@url,"darwin-arm64")]][1]'
version=$(xmlstarlet sel \
  -N sparkle=http://www.andymatuschak.org/xml-namespaces/sparkle \
  -t -v "${xpath}/sparkle:shortVersionString" "$appcast_path")
if [[ -z $version ]]; then
  version=$(xmlstarlet sel \
    -N sparkle=http://www.andymatuschak.org/xml-namespaces/sparkle \
    -t -v "${xpath}/title" "$appcast_path")
fi
[[ ${#version} -le 128 && $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || {
  printf 'codex-app: invalid appcast version\n' >&2
  exit 1
}
url_count=$(xmlstarlet sel \
  -N sparkle=http://www.andymatuschak.org/xml-namespaces/sparkle \
  -t -v "count(${xpath}/enclosure[contains(@url,'darwin-arm64')]/@url)" "$appcast_path")
[[ $url_count == 1 ]] || {
  printf 'codex-app: expected one darwin arm64 enclosure\n' >&2
  exit 1
}
url=$(xmlstarlet sel \
  -N sparkle=http://www.andymatuschak.org/xml-namespaces/sparkle \
  -t -v "${xpath}/enclosure[contains(@url,'darwin-arm64')]/@url" "$appcast_path")
expected_url="https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-${version}.zip"
[[ $url == "$expected_url" ]] || {
  printf 'codex-app: unexpected appcast download URL\n' >&2
  exit 1
}

archive_metadata=$(nix store prefetch-file --json "$url")
archive_path=$(jq -er .storePath <<<"$archive_metadata")
hash=$(jq -er .hash <<<"$archive_metadata")
mapfile -t plist_paths < <(unzip -Z1 "$archive_path" | rg '^[^/]+\.app/Contents/Info\.plist$')
[[ ${#plist_paths[@]} == 1 ]] || {
  printf 'codex-app: expected one top-level app Info.plist\n' >&2
  exit 1
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-app-update.XXXXXX")
pin_tmp=$(mktemp "${pin_path}.tmp.XXXXXX")
trap 'rm -rf -- "$work_dir"; rm -f -- "$pin_tmp"' EXIT
unzip -p "$archive_path" "${plist_paths[0]}" >"$work_dir/Info.plist"
plistutil -i "$work_dir/Info.plist" -o "$work_dir/Info.json" -f json

plist_value() {
  local key=$1
  jq -r --arg key "$key" '.[$key] // empty | select(type == "string")' \
    "$work_dir/Info.json"
}

app_name=${plist_paths[0]%%/*}
bundle_identifier=$(plist_value CFBundleIdentifier)
display_name=$(plist_value CFBundleDisplayName)
if [[ -z $display_name ]]; then
  display_name=$(plist_value CFBundleName)
fi
bundle_version=$(plist_value CFBundleShortVersionString)
expected_app_name=$(jq -er .appName "$pin_path")
expected_bundle_identifier=$(jq -er .bundleIdentifier "$pin_path")
expected_display_name=$(jq -er .displayName "$pin_path")
[[ $app_name == "$expected_app_name" ]] || {
  printf 'codex-app: unexpected app bundle name\n' >&2
  exit 1
}
[[ $bundle_identifier == "$expected_bundle_identifier" ]] || {
  printf 'codex-app: unexpected bundle identifier\n' >&2
  exit 1
}
[[ $display_name == "$expected_display_name" ]] || {
  printf 'codex-app: unexpected bundle display name\n' >&2
  exit 1
}
[[ $bundle_version == "$version" ]] || {
  printf 'codex-app: bundle version does not match appcast\n' >&2
  exit 1
}

jq --arg version "$version" --arg url "$url" --arg hash "$hash" '
  .version = $version | .url = $url | .hash = $hash
' "$pin_path" >"$pin_tmp"
if ! cmp -s "$pin_tmp" "$pin_path"; then
  mv "$pin_tmp" "$pin_path"
fi
