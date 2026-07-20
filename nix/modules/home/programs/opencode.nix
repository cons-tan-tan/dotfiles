{
  config,
  pkgs,
  ...
}:
let
  herdrOpenCodeIntegration = pkgs.dotfilesPackages.herdr.integrations.opencode;
  models = import ../../../lib/settings/models.nix;
in
{
  programs.opencode = {
    enable = true;
    settings = {
      model = models.opencode.model;
      provider = {
        openai = {
          models = {
            "gpt-5.6-sol" = {
              options = {
                reasoningEffort = models.opencode.reasoningEffort;
              };
            };
          };
        };
      };
      # instructions は opencode 側で glob 展開される (claude.nix が配置する
      # ~/.claude 配下の symlink に依存)。
      instructions = [
        "${config.home.homeDirectory}/.claude/output-styles/faust.md"
        "${config.home.homeDirectory}/.claude/rules/*.md"
      ];
      command = {
        # agents/skills/commit (~/.agents/skills/commit に配置) を呼ぶ
        commit = {
          description = "Call commit skill";
          template = "Call commit skill and follow it.";
        };
      };
    };
    tui = {
      theme = "lucent-orng";
    };
    themes = {
      transparent = {
        defs = { };
        theme = {
          primary = "#88C0D0";
          secondary = "#81A1C1";
          accent = "#8FBCBB";
          text = "#ECEFF4";
          textMuted = "#b7b9be";
          background = "none";
          backgroundPanel = "none";
          backgroundElement = "none";
        };
      };
    };
  };

  home.file.".config/opencode/command".source =
    config.lib.file.mkOutOfStoreSymlink "${config.my.dotfilesDir}/claude/commands";

  home.file.".config/opencode/plugins/herdr-agent-state.js".source =
    "${herdrOpenCodeIntegration}/plugins/herdr-agent-state.js";
}
