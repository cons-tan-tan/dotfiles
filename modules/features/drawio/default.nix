{ inputs, ... }:
{
  flake-file.inputs.drawio-skill = {
    url = "github:jgraph/drawio-mcp";
    flake = false;
  };

  features.drawio-agent-skill = {
    name = "feature/drawio/agent-skill";
    agent-skills = [
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

  features.drawio-linux-headless = {
    name = "feature/drawio/linux-headless";
    # The agent and platform bundles meet again at each home. Including the
    # sibling skill here would therefore emit its quirk contribution twice.
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.drawio-headless ];
    };
  };
}
