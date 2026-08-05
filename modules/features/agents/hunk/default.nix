{
  features,
  inputs,
  ...
}:
{
  flake-file.inputs.hunk = {
    url = "github:modem-dev/hunk";
    inputs.bun2nix.follows = "bun2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  features.agent-hunk = {
    name = "feature/agents/hunk";
    includes = [ features.agent-skills-consumer ];
    agent-skills = [
      {
        name = "hunk-review";
        provenance = "external";
        definition.root = inputs.hunk.outPath + "/skills/hunk-review";
      }
    ];
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ./_lib/home.nix {
        inherit
          config
          inputs
          lib
          pkgs
          ;
      };
  };

  features.agent-hunk-wsl = {
    name = "feature/agents/hunk/wsl";
    homeManager = { pkgs, ... }: {
      programs.hunk.package = pkgs.dotfilesPackages.hunk.wslRuntime;
    };
  };
}
