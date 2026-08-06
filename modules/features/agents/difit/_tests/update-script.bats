#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture DIFIT_UPDATE_TEST_FIXTURE 'difit updater dependencies'
}

@test "difit updater advances its paired input before delegating hashes to nix-update" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local stubs="$BATS_TEST_TMPDIR/stubs"
  local metadata="$BATS_TEST_TMPDIR/metadata.json"
  local calls="$BATS_TEST_TMPDIR/calls"
  local module=modules/features/agents/difit/default.nix
  local pin=modules/features/agents/difit/_packages/difit/pin.json
  mkdir -p "$repo/$(dirname "$module")" "$repo/$(dirname "$pin")" "$stubs"
  git -C "$repo" init --quiet
  printf 'source = "github:yoshiko-pg/difit/v1.0.0";\n' >"$repo/$module"
  printf '{}\n' >"$repo/$pin"
  jq -n '{version: "2.0.0"}' >"$metadata"

  write_bash_stub "$stubs/nix" <<'SH'
if [[ ${1:-} == store ]]; then
  jq -n --arg storePath "$UPDATE_METADATA" '{storePath: $storePath}'
  exit 0
fi
printf 'nix' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
SH
  write_bash_stub "$stubs/nix-update" <<'SH'
printf 'nix-update' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
SH

  run env \
    PATH="$stubs:$PATH" \
    UPDATE_CALLS="$calls" \
    UPDATE_METADATA="$metadata" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/difit/_scripts/update.sh"
  [ "$status" -eq 0 ]
  rg -F 'github:yoshiko-pg/difit/v2.0.0' "$repo/$module"
  [ "$(<"$calls")" = $'nix <run> <.#write-flake>\nnix <flake> <update> <difit-src>\nnix-update <--file> <modules/features/nixpkgs/_interface/nix-update-package-set.nix> <--version> <skip> <--override-filename> <modules/features/agents/difit/_packages/difit/pin.json> <difit>' ]
}
