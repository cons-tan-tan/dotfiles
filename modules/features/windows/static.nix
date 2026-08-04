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
              source = "${config.dotfiles.platform.source}/agents/context/global.md";
              destination = ".claude/CLAUDE.md";
            }
          ];
          trees = [
            {
              source = "${config.dotfiles.platform.source}/agents/context/rules";
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
              source = "${config.dotfiles.platform.source}/claude/commands";
              destination = ".claude/commands";
            }
            {
              source = "${config.dotfiles.platform.source}/claude/output-styles";
              destination = ".claude/output-styles";
            }
            {
              source = "${config.dotfiles.platform.source}/claude/hooks";
              destination = ".claude/hooks";
            }
            {
              source = "${config.home.homeDirectory}/.claude/skills";
              destination = ".claude/skills";
              excludes = [ "ax/" ];
            }
            {
              source = "${config.home.homeDirectory}/.agents/skills";
              destination = ".agents/skills";
              excludes = [ "ax/" ];
            }
          ];
        };
      };
  };
}
