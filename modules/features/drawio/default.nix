{ inputs, ... }:
{
  flake-file.inputs.drawio-skill = {
    url = "github:jgraph/drawio-mcp";
    flake = false;
  };

  flake.modules.homeManager.drawio-agent-skill = {
    key = "modules/features/drawio/default.nix#homeManager.drawio-agent-skill";
    dotfiles.agentSkillContributions = [
      {
        name = "drawio";
        provenance = "external";
        definition = {
          root = inputs.drawio-skill.outPath + "/plugins/claude-code/skills/drawio";
          customization.body.program = ./_data/agent-skills/drawio;
        };
      }
    ];
  };

  flake.modules.homeManager.drawio-linux-headless = { pkgs, ... }: {
    key = "modules/features/drawio/default.nix#homeManager.drawio-linux-headless";
    home.packages = [ pkgs.dotfilesPackages.drawio-headless ];
  };
}
