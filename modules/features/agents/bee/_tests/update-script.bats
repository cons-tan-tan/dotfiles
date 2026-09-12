#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture BEE_UPDATE_TEST_FIXTURE 'bee updater dependencies'
  export UPDATE_CALLS="$BATS_TEST_TMPDIR/calls"
  export UPDATE_METADATA="$BATS_TEST_TMPDIR/metadata.json"
  repo="$BATS_TEST_TMPDIR/repo"
  stubs="$BATS_TEST_TMPDIR/stubs"
  module=modules/features/agents/bee/default.nix
  mkdir -p "$repo/$(dirname "$module")" "$stubs"
  git -C "$repo" init --quiet
  printf 'source = "github:nulab/bee/v1.0.0";\n' >"$repo/$module"
  jq -n '{version: "2.0.0"}' >"$UPDATE_METADATA"

  write_bash_stub "$stubs/nix" <<'SH'
if [[ ${1:-} == store ]]; then
  jq -n --arg storePath "$UPDATE_METADATA" '{storePath: $storePath}'
  exit 0
fi
printf 'nix' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
SH
  write_bash_stub "$stubs/npm" <<'SH'
printf 'npm' >>"$UPDATE_CALLS"
printf ' <%s>' "$@" >>"$UPDATE_CALLS"
printf '\n' >>"$UPDATE_CALLS"
exit "${UPDATE_NPM_STATUS:-0}"
SH
}

run_updater() {
  run env PATH="$stubs:$PATH" bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/bee/_scripts/update.sh"
}

@test "bee updater pins npm dependencies and skills to the same release" {
  run_updater
  [ "$status" -eq 0 ]
  rg -F 'github:nulab/bee/v2.0.0' "$repo/$module"
  [ "$(<"$UPDATE_CALLS")" = $'npm <install> <--prefix> <modules/features/agents/bee/_packages/bee/node> <--package-lock-only> <--ignore-scripts> <--no-audit> <--no-fund> <--save-exact> <@nulab/bee@2.0.0>\nnix <run> <.#write-flake>\nnix <flake> <update> <bee-src>' ]
}

@test "bee updater rejects invalid release metadata before changing inputs" {
  jq -n '{version: "not-a-version"}' >"$UPDATE_METADATA"
  run_updater
  [ "$status" -ne 0 ]
  [[ "$output" == *"bee: unsupported release version"* ]]
  rg -F 'github:nulab/bee/v1.0.0' "$repo/$module"
  [ ! -e "$UPDATE_CALLS" ]
}

@test "bee updater does not advance skills when npm resolution fails" {
  export UPDATE_NPM_STATUS=1
  run_updater
  [ "$status" -ne 0 ]
  rg -F 'github:nulab/bee/v1.0.0' "$repo/$module"
  ! rg '^nix' "$UPDATE_CALLS"
}
