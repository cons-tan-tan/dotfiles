final: prev:
let
  llm = prev._llm-agents.packages.${prev.stdenv.hostPlatform.system};
in
{
  # LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
  inherit (llm)
    codex
    claude-code
    opencode
    pi
    ccusage
    agent-browser
    ;
}
