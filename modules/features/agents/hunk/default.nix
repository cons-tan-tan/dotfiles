{ inputs, ... }:
{
  flake-file.inputs.hunk = {
    url = "github:modem-dev/hunk";
    inputs.bun2nix.follows = "bun2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  features.agent-hunk = {
    name = "feature/agents/hunk";
    agent-skills = [
      {
        name = "hunk-review";
        provenance = "external";
        definition.root = inputs.hunk.outPath + "/skills/hunk-review";
      }
    ];
  };

  features.agent-hunk-wsl = {
    name = "feature/agents/hunk/wsl";
    homeManager = { pkgs, ... }: {
      programs.hunk.package = pkgs.dotfilesPackages.hunk.wslRuntime;
    };
  };
}
