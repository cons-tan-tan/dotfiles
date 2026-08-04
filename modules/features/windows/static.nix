{ ... }:
{
  features.windows-static = {
    name = "feature/windows/static";
    windows =
      { config, ... }:
      {
        dotfiles.windows.staticResources.claude = {
          directories = [
            ".claude"
            ".agents/skills"
          ];
          files = [
            {
              source = "${config.dotfiles.windows.source}/agents/context/global.md";
              destination = ".claude/CLAUDE.md";
            }
          ];
          trees = [
            {
              source = "${config.dotfiles.windows.source}/agents/context/rules";
              destination = ".claude/rules";
              excludes = [
                "nix.md"
                "nix.md.license"
                "tools.md"
                "tools.md.license"
                "web-fetch.md"
                "web-fetch.md.license"
              ];
            }
            {
              source = "${config.dotfiles.windows.source}/claude/commands";
              destination = ".claude/commands";
            }
            {
              source = "${config.dotfiles.windows.source}/claude/output-styles";
              destination = ".claude/output-styles";
            }
            {
              source = "${config.dotfiles.windows.source}/claude/hooks";
              destination = ".claude/hooks";
            }
            {
              source = "${config.dotfiles.windows.linuxHomedir}/.claude/skills";
              destination = ".claude/skills";
              excludes = [ "ax/" ];
            }
            {
              source = "${config.dotfiles.windows.linuxHomedir}/.agents/skills";
              destination = ".agents/skills";
              excludes = [ "ax/" ];
            }
          ];
        };
      };
  };
}
