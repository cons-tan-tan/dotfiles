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
    homeManager =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      import ./_lib/home/hunk.nix {
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
    includes = [ features.agent-hunk ];
    homeManager = { pkgs, ... }: {
      programs.hunk.package = pkgs.dotfilesPackages.hunk.wslRuntime;
    };
  };
}
