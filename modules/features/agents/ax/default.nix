{
  features,
  inputs,
  ...
}:
{
  flake-file.inputs.ax = {
    url = "github:yusukebe/ax/v0.1.23";
    inputs.bun2nix.follows = "bun2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  features.agent-ax = {
    name = "feature/agents/ax";
    includes = [ features.agent-skills-consumer ];
    agent-skills = [
      {
        name = "ax";
        provenance = "external";
        definition.root = inputs.ax.outPath + "/skills/ax";
      }
    ];
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax ];
      };
  };
}
