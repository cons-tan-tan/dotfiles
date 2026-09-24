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

  flake.modules.homeManager.shell-direnv = {
    key = "modules/features/shell/direnv.nix#homeManager.shell-direnv";
    imports = [ inputs.direnv-instant.homeModules.direnv-instant ];

    programs = {
      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
      direnv-instant.enable = true;
    };
  };
}
