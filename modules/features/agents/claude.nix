{
  features,
  inputs,
  ...
}:
{
  flake-file.inputs.codex-plugin-cc = {
    url = "github:openai/codex-plugin-cc";
    flake = false;
  };

  features.agent-claude = {
    name = "feature/agents/claude";
    includes = [
      features.agents-base
      features.agent-herdr
    ];
    cli-tools = [
      {
        id = "claude-code";
        nix.route = "dotfiles-package";
        winget = {
          packageId = "Anthropic.ClaudeCode";
          description = "Claude Code CLI";
        };
      }
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ./_lib/home/claude.nix {
        inherit
          config
          inputs
          lib
          pkgs
          ;
      };
  };
}
