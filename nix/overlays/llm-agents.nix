final: prev: {
  # LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
  inherit (prev._llm-agents.packages.${prev.stdenv.hostPlatform.system})
    ccusage
    ccusage-codex
    claude-code
    ;
}
