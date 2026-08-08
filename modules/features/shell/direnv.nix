{ inputs, ... }:
{
  flake-file.inputs.direnv-instant = {
    url = "github:Mic92/direnv-instant";
    inputs = {
      flake-parts.follows = "flake-parts";
      nixpkgs.follows = "nixpkgs";
      treefmt-nix.follows = "treefmt-nix";
    };
  };

  features.shell-direnv = {
    name = "feature/shell/direnv";
    homeManager = {
      imports = [ inputs.direnv-instant.homeModules.direnv-instant ];

      programs = {
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
        direnv-instant.enable = true;
      };
    };
  };
}
