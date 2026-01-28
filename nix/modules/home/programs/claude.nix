{ config, dotfilesDir, ... }:
{
  programs.claude-code = {
    enable = true;
    settings = {
      includeCoAuthoredBy = false;
      language = "japanese";
      model = "claude-opus-4-5-20251101";
      env = {
        USE_BUILTIN_RIPGREP = "0";
      };
    };
  };

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/skills".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/skills";
  home.file.".claude/rules".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/rules";
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/output-styles";
}
