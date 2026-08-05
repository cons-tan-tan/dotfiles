{ features, ... }:
{
  flake-file.inputs.llm-agents.url = "github:numtide/llm-agents.nix";

  features.agents-default = {
    name = "feature/agents/default";
    includes = [
      features.agents-base
      features.agent-skills
      features.agent-ax
      features.agent-ccusage
      features.agent-copilot
      features.agent-gemini
      features.agent-guidance
      features.agent-browser
      features.agent-claude
      features.agent-codex
      features.agent-difit
      features.agent-hcom
      features.agent-herdr
      features.agent-hunk
      features.agent-opencode
      features.agent-pi
      features.agent-slack
    ];
  };
}
