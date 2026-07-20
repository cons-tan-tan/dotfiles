# LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
{
  llm-agents,
  agent-browser-skill,
}:
final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  llm = llm-agents.packages.${system};
  agent-browser = prev.callPackage ../packages/agent-browser {
    agentBrowserSource = agent-browser-skill;
  };
  herdrPackages = prev.callPackage ../packages/herdr { };
in
{
  inherit (llm)
    codex
    claude-code
    opencode
    pi
    ccusage
    ;

  inherit agent-browser;

  inherit (herdrPackages)
    herdr
    herdr-agent-skill
    herdr-agent-plugin
    herdr-claude-integration
    herdr-codex-integration
    herdr-pi-integration
    herdr-opencode-integration
    herdr-codex-marketplace
    ;
}
