# LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
llm-agents: final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  llm = llm-agents.packages.${system};
  herdrPackages = prev.callPackage ../packages/herdr {
    inherit llm-agents;
  };
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

  inherit (herdrPackages)
    herdr
    herdr-agent-skill
    herdr-agent-plugin
    herdr-claude-integration
    herdr-codex-integration
    herdr-pi-integration
    herdr-codex-marketplace
    ;
}
