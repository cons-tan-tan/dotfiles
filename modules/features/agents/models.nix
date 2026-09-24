{ lib, ... }:
let
  # Updating model IDs is a deliberate runtime choice, separate from package pins.
  codexFamilyModel = "gpt-5.6-sol";
in
{
  flake.modules.homeManager.agents-base = {
    key = "modules/features/agents/models.nix#homeManager.agents-base";
    options.dotfiles.agentModels = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      description = "Shared model choices for agent features.";
    };
    config.dotfiles.agentModels = {
      claude = {
        main = "claude-opus-4-7[1m]";
        sonnet = "claude-sonnet-5";
      };

      codex = {
        model = codexFamilyModel;
        reasoningEffort = "high";
      };

      pi = {
        provider = "openai-codex";
        model = codexFamilyModel;
        thinkingLevel = "high";
      };

      opencode = {
        model = "openai/${codexFamilyModel}";
        reasoningEffort = "high";
      };
    };
  };
}
