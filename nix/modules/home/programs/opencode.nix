{
  config,
  dotfilesDir,
  ...
}:
{
  programs.opencode = {
    enable = true;
    settings = {
      theme = "lucent-orng";
      instructions = [
        "${config.home.homeDirectory}/.claude/output-styles/faust.md"
      ];
      command = {
        git-commit-crafter = {
          description = "Call git-commit-crafter skill";
          template = "Call git-commit-crafter skill and follow it. Ask any required questions before proceeding.";
        };
      };
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
