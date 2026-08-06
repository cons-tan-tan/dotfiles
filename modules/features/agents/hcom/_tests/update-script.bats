#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"
source "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/_tests/paired-release-update-helper.bash"

setup() {
  require_nix_fixture HCOM_UPDATE_TEST_FIXTURE 'hcom updater dependencies'
}

@test "hcom updater synchronizes assets and its paired flake input" {
  run_paired_release_update_contract \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/hcom/_scripts/update.sh" \
    hcom \
    aannoo/hcom \
    hcom-src \
    modules/features/agents/hcom/default.nix \
    modules/features/agents/hcom/_packages/hcom/pin.json
}
