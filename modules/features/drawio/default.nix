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
          customization.body =
            { original, ... }:
            ''

              > **Local override**: when running on WSL2, use `drawio` from `$PATH`
              > for exports. The managed Linux headless wrapper already injects
              > `--no-sandbox`, `--disable-gpu`, and starts Xvfb / D-Bus. In that
              > environment, do not add these flags or call `/mnt/c/.../draw.io.exe`;
              > the "Opening the result" instructions below still apply.
            ''
            + original;
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
