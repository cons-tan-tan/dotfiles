# LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
llm-agents: final: prev:
let
  llm = llm-agents.packages.${prev.stdenv.hostPlatform.system};
in
{
  inherit (llm)
    codex
    claude-code
    opencode
    pi
    ccusage
    agent-browser
    ;
}
