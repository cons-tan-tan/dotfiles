{
  # nixd consumes the root flake-parts option declarations through
  # `flake.debug.options`; Den's `flake-parts` class is perSystem-scoped.
  debug = true;

  features.development-nix = {
    name = "feature/development/nix";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.nixd ];
      };
  };
}
