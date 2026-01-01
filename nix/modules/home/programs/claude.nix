{ config, dotfilesDir, ... }:
{
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/skills".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/skills";
}
