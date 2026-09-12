{ inputs, ... }:
{
  # Keep the CLI and its command reference skills on the same release.
  flake-file.inputs.bee-src = {
    url = "github:nulab/bee/v1.1.1";
    flake = false;
  };

  features.agent-bee = {
    name = "feature/agents/bee";
    agent-skills =
      map
        (name: {
          inherit name;
          provenance = "external";
          definition.root = inputs.bee-src.outPath + "/skills/${name}";
        })
        [
          "using-bee"
          "backlog-notation"
        ];
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.bee ];
    };
  };
}
