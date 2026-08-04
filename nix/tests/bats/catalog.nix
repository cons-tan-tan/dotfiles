{
  ciCheck,
  workflowFiles,
}:
[
  {
    name = "update-pins-e2e";
    fixture = "updatePins";
    testFiles = [ "bats/update-pins.bats" ];
    sourceFiles = [
      "flake.lock"
      "flake.nix"
      "modules/features/agents/inputs/agent-browser-skill.nix"
      "modules/features/agents/inputs/agent-slack-skill.nix"
      "modules/features/agents/inputs/difit-src.nix"
      "modules/features/agents/inputs/hcom-src.nix"
      "modules/features/agents/hunk.nix"
      "nix/packages/agent-command-guard/Cargo.lock"
      "nix/packages/agent-command-guard/Cargo.toml"
      "nix/packages/shellfirm/Cargo.lock"
      "nix/pins/agent-browser.json"
      "nix/pins/agent-slack.json"
      "nix/pins/codex-app.json"
      "nix/pins/difit.json"
      "nix/pins/hcom.json"
      "nix/pins/shellfirm.json"
      "bats/test-helper.bash"
    ];
    initializeGit = true;
    platformPredicate = _platform: true;
  }
  {
    name = "safe-fetch-e2e";
    fixture = "safeFetch";
    testFiles = [
      "bats/curl-fetch.bats"
      "bats/gh-api-get.bats"
    ];
    sourceFiles = [ "bats/test-helper.bash" ];
    initializeGit = false;
    platformPredicate = _platform: true;
  }
  {
    name = "rust-cli-e2e";
    fixture = "rustCli";
    testFiles = [
      "bats/apply-nix-settings.bats"
      "bats/apply-secrets.bats"
    ];
    sourceFiles = [ "bats/test-helper.bash" ];
    initializeGit = false;
    platformPredicate = _platform: true;
  }
  {
    name = "shell-wrapper-tests";
    fixture = "shellWrappers";
    testFiles = [
      "bats/apply-winget.bats"
      "bats/aws-config-activation.bats"
      "bats/aws-login.bats"
      "bats/claude-wrapper.bats"
      "bats/codex-wrapper.bats"
      "bats/darwin-apps.bats"
      "bats/drawio-headless.bats"
      "bats/ghq-fetch-all.bats"
      "bats/herdr-wrapper.bats"
      "bats/linux-host-apps.bats"
      "bats/nh-clean-growth-runner.bats"
      "bats/nh-cleanup-systemd.bats"
      "bats/nh-result-root-pruner.bats"
      "bats/nix-store-growth-checker.bats"
      "bats/pi-package-manager.bats"
      "bats/pi-wrapper.bats"
      "bats/wsl-open.bats"
      "bats/wsl-set-ssh-auth-sock.bats"
      "bats/windows-companion-deploy.bats"
    ];
    sourceFiles = [
      "nix/apps/apply-winget.sh"
      "nix/apps/darwin-build.sh"
      "nix/apps/darwin-switch.sh"
      "nix/apps/linux-host-build.sh"
      "nix/apps/linux-host-switch.sh"
      "nix/packages/wsl-open/wsl-open.sh"
      "nix/packages/aws/aws-login.sh"
      "nix/packages/aws/reconcile-package.nix"
      "nix/packages/claude-code/claude-wrapper.sh"
      "nix/packages/codex/codex-wrapper.sh"
      "nix/packages/drawio-headless/drawio-wrapper.sh"
      "nix/packages/ghq-fetch-all/ghq-fetch-all.sh"
      "nix/packages/herdr/herdr-wrapper.sh"
      "nix/packages/nh-cleanup-systemd/install-nh-cleanup-systemd.sh"
      "nix/packages/nh-clean-growth-runner/nh-clean-growth-runner.sh"
      "nix/packages/nh-result-root-pruner/nh-prune-result-roots.sh"
      "nix/packages/nix-store-growth-checker/nix-store-growth-checker.sh"
      "nix/packages/pi/package-manager.sh"
      "nix/packages/pi/pi-wrapper.sh"
      "nix/packages/wsl-set-ssh-auth-sock/set-ssh-auth-sock.sh"
      "nix/packages/windows-companion-deploy/deploy.sh"
      "bats/test-helper.bash"
    ];
    initializeGit = true;
    platformPredicate = _platform: true;
  }
  {
    name = "workflow-policy-tests";
    # Repository policy owns stable declarations, not validator diagnostic
    # wording; otherwise validator upgrades would require unrelated Bats edits.
    # Its inputs are repository bytes, so Darwin cannot add platform signal.
    fixture = "workflowPolicy";
    ciTargets = ciCheck.targets.linux "rust-and-bats";
    testFiles = [ "bats/workflow-policy.bats" ];
    sourceFiles = workflowFiles ++ [ "bats/test-helper.bash" ];
    initializeGit = false;
    platformPredicate = _platform: true;
  }
]
