{ lib, ... }:
{
  flake.modules.homeManager.agents-base = {
    key = "modules/features/agents/models.nix#homeManager.agents-base";
    options.dotfiles.agentModels = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      description = "Shared model choices for agent features.";
    };
    # Updating model IDs is a deliberate runtime choice, separate from package pins.
    config.dotfiles.agentModels = {
      claude = {
        main = "claude-opus-5-5";
      };

      codex = {
        model = "gpt-6.1-sol";
        reasoningEffort = "xhigh";
      };

      pi = {
        provider = "openai-codex";
        model = "gpt-5.6-sol";
        thinkingLevel = "high";
      };
    };
  };
}
