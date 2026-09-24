{ inputs, ... }:
{
  # Keep the CLI and its command reference skills on the same release.
  flake-file.inputs.bee-src = {
    url = "github:nulab/bee/v1.1.1";
    flake = false;
  };

  flake.modules.homeManager.agent-bee = {
    key = "modules/features/agents/bee/default.nix#homeManager.agent-bee";
    imports = [
      ({ pkgs, ... }: {
        home.packages = [ pkgs.dotfilesPackages.bee ];
      })
    ];
    dotfiles.agentSkillContributions =
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
  };
}
