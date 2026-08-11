{
  features,
  inputs,
  ...
}:
{
  # nixd consumes the root flake-parts option declarations through
  # `flake.debug.options`; Den's `flake-parts` class is perSystem-scoped.
  debug = true;

  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  features.nix-default = {
    name = "feature/nix/default";
    includes = [ features.nix-command-policy ];

    homeManager =
      { pkgs, ... }:
      {
        imports = [ inputs.nix-index-database.homeModules.default ];
        programs.nix-index-database.comma.enable = true;
        home.packages = [ pkgs.nixd ];
      };
  };
}
