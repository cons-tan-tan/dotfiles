{ inputs, ... }:
{
  flake-file.inputs.agent-browser-skill = {
    url = "github:vercel-labs/agent-browser/v0.31.1";
    flake = false;
  };

  flake.modules.homeManager.agent-browser = {
    key = "modules/features/agents/browser/default.nix#homeManager.agent-browser";
    imports = [
      ({ pkgs, ... }: {
        home.packages = [ pkgs.dotfilesPackages.agent-browser ];
      })
    ];
    dotfiles.agentSkillContributions = [
      {
        name = "agent-browser";
        provenance = "external";
        definition = {
          root = inputs.agent-browser-skill.outPath + "/skills/agent-browser";
          customization.frontmatter = {
            inheritFields = [ "hidden" ];
            excludeFields = [ "allowed-tools" ];
            description = "Controls headless browser sessions through the agent-browser CLI when tasks require scripted navigation, form filling, clicks, authentication, screenshots, data extraction, or web application testing.";
          };
        };
      }
    ];
  };
}
