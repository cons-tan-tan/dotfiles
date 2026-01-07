{ config, dotfilesDir, ... }:
{
  programs.claude-code = {
    enable = true;
    settings = {
      includeCoAuthoredBy = false;
      model = "claude-opus-4-5-20251101";
    };
  };
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/skills".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/skills";
  # Note: Faust output style is a fan-made derivative work based on the character from Limbus Company.
  # Limbus Company and all related characters are © Project Moon.
  # Created under Project Moon's Fanwork Guidelines.
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/output-styles";
}
