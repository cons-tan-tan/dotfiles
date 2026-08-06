#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"
source "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/_tests/paired-release-update-helper.bash"

setup() {
  require_nix_fixture AGENT_BROWSER_UPDATE_TEST_FIXTURE 'agent-browser updater dependencies'
}

@test "agent-browser updater synchronizes assets and its paired flake input" {
  run_paired_release_update_contract \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/browser/_scripts/update.sh" \
    agent-browser \
    vercel-labs/agent-browser \
    agent-browser-skill \
    modules/features/agents/browser/default.nix \
    modules/features/agents/browser/_packages/agent-browser/pin.json
}
