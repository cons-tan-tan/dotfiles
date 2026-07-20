# LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
llm-agents: _final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  llm = llm-agents.packages.${system};
in
{
  inherit (llm)
    codex
    claude-code
    opencode
    pi
    ccusage
    ;
}
