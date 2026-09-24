{ inputs, ... }:
{
  # nixd consumes the root flake-parts option declarations through
  # `flake.debug.options`.
  debug = true;

  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.homeManager.nix-default = { pkgs, ... }: {
    key = "modules/features/nix/default.nix#homeManager.nix-default";
    imports = [ inputs.nix-index-database.homeModules.default ];
    programs.nix-index-database.comma.enable = true;
    home.packages = [ pkgs.nixd ];
  };
}
