#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"
source "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/_tests/paired-release-update-helper.bash"

setup() {
  require_nix_fixture AGENT_SLACK_UPDATE_TEST_FIXTURE 'agent-slack updater dependencies'
}

@test "agent-slack updater synchronizes assets and its paired flake input" {
  run_paired_release_update_contract \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/slack/_scripts/update.sh" \
    agent-slack \
    stablyai/agent-slack \
    agent-slack-skill \
    modules/features/agents/slack/default.nix \
    modules/features/agents/slack/_packages/agent-slack/pin.json
}
