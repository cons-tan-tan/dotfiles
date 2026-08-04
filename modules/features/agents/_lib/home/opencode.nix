{
  config,
  lib,
  pkgs,
  ...
}:
let
  herdrOpenCodeIntegration = pkgs.dotfilesPackages.herdr.integrations.opencode;
  models = import ../settings/models.nix;
  openaiModelName = lib.removePrefix "openai/" models.opencode.model;
in
{
  programs.opencode = {
    enable = true;
    settings = {
      model = models.opencode.model;
      provider = {
        openai = {
          models = {
            ${openaiModelName} = {
              options = {
                reasoningEffort = models.opencode.reasoningEffort;
              };
            };
          };
        };
      };
      # instructions はopencode側でglob展開される。共通contextを先に読み、
      # tool固有のoutput styleを最後に追加する。
      instructions = [
        "${config.home.homeDirectory}/.agents/context/global.md"
        "${config.home.homeDirectory}/.agents/context/rules/*.md"
        "${config.home.homeDirectory}/.claude/output-styles/faust.md"
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
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles.platform.source}/claude/commands";

  home.file.".config/opencode/plugins/herdr-agent-state.js".source =
    "${herdrOpenCodeIntegration}/plugins/herdr-agent-state.js";
}
