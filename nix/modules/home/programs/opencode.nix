{
  config,
  dotfilesDir,
  ...
}:
{
  programs.opencode = {
    enable = true;
    settings = {
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
          # Required fields
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
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
}
