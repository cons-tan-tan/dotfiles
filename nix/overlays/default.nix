final: prev:
let
  # Import all overlay files in this directory
  overlayFiles = [
    # LLM agents
    ./llm-agents.nix
    # Rust tools
    ./rustup.nix
    # Git worktree manager
    ./git-wt.nix
    # Slack automation CLI for AI agents
    ./agent-slack.nix
    # WSL2-compatible drawio-headless replacement
    ./drawio-headless.nix
  ];

  # Apply each overlay and merge results
  applyOverlays = builtins.foldl' (acc: overlay: acc // (import overlay final prev)) { } overlayFiles;
in
applyOverlays
