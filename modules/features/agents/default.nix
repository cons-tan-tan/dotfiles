{ config, ... }:
{
  flake-file.inputs.llm-agents.url = "github:numtide/llm-agents.nix";

  flake.modules.homeManager.agents-default = {
    key = "modules/features/agents/default.nix#homeManager.agents-default";
    imports = [
      config.flake.modules.homeManager.agents-base
      config.flake.modules.homeManager.agent-skills
      config.flake.modules.homeManager.agent-ax
      config.flake.modules.homeManager.agent-ccusage
      config.flake.modules.homeManager.agent-copilot
      config.flake.modules.homeManager.agent-gemini
      config.flake.modules.homeManager.agent-guidance
      config.flake.modules.homeManager.agent-bee
      config.flake.modules.homeManager.agent-browser
      config.flake.modules.homeManager.agent-claude
      config.flake.modules.homeManager.agent-codex
      config.flake.modules.homeManager.agent-difit
      config.flake.modules.homeManager.agent-hcom
      config.flake.modules.homeManager.agent-herdr
      config.flake.modules.homeManager.agent-hunk
      config.flake.modules.homeManager.agent-opencode
      config.flake.modules.homeManager.agent-pi
      config.flake.modules.homeManager.agent-slack
    ];
  };
}
