run_paired_release_update_contract() {
  local script=$1
  local label=$2
  local repository=$3
  local input_name=$4
  local module_path=$5
  local pin_path=$6
  local asset_name="${label}-fixture"
  local fixture_root="$BATS_TEST_TMPDIR/${label}"
  local repo="$fixture_root/repo"
  local stubs="$fixture_root/stubs"
  local release_json="$fixture_root/release.json"
  local calls="$fixture_root/calls"

  mkdir -p "$repo/$(dirname "$module_path")" "$repo/$(dirname "$pin_path")" "$stubs"
  git -C "$repo" init --quiet
  printf 'source = "github:%s/v1.0.0";\n' "$repository" >"$repo/$module_path"
  jq -n --arg name "$asset_name" '
    {assets: {"x86_64-linux": {name: $name, hash: "sha256-old"}}}
  ' >"$repo/$pin_path"
  jq -n \
    --arg name "$asset_name" \
    --arg url "https://github.com/${repository}/releases/download/v2.0.0/${asset_name}" '
    {
      tag_name: "v2.0.0",
      assets: [{name: $name, state: "uploaded", browser_download_url: $url}]
    }
  ' >"$release_json"

  write_bash_stub "$stubs/gh-api-get" <<'SH'
cat "$UPDATE_RELEASE_JSON"
SH
  write_bash_stub "$stubs/nix" <<'SH'
if [[ ${1:-} == store && ${2:-} == prefetch-file ]]; then
  printf '{"hash":"sha256-new"}\n'
  exit 0
fi
printf 'nix' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
SH

  run env \
    PATH="$stubs:$PATH" \
    UPDATE_CALLS="$calls" \
    UPDATE_RELEASE_JSON="$release_json" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" "$script"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.assets["x86_64-linux"].hash' "$repo/$pin_path")" = sha256-new ]
  rg -F "github:${repository}/v2.0.0" "$repo/$module_path"
  [ "$(<"$calls")" = $'nix <run> <.#write-flake>\nnix <flake> <update> <'"$input_name"'>' ]

  jq '.tag_name = "v2.0.0${builtins.readFile ./flake.nix}"' \
    "$release_json" >"$release_json.tmp"
  mv "$release_json.tmp" "$release_json"
  : >"$calls"
  run env \
    PATH="$stubs:$PATH" \
    UPDATE_CALLS="$calls" \
    UPDATE_RELEASE_JSON="$release_json" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" "$script"
  [ "$status" -eq 1 ]
  [[ $output == *"unsupported release tag"* ]]
  [ ! -s "$calls" ]
}
