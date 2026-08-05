_:
let
  payload = import ./_interface/payload.nix;
in
{
  features.agent-guidance = {
    name = "feature/agents/guidance";
    windows =
      { config, ... }:
      let
        contextRoot = "${config.dotfiles.platform.source}/${payload.repositoryRelative.contextRoot}";
      in
      {
        dotfiles.windows.staticResources.guidance = {
          files = [
            {
              source = "${contextRoot}/global.md";
              destination = ".claude/CLAUDE.md";
            }
          ];
          trees = [
            {
              source = "${contextRoot}/rules";
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
          ];
        };
      };
  };
}
