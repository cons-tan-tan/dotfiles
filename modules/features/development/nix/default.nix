{ ... }:
{
  features.development-nix = {
    name = "feature/development/nix";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.nixd ];
      };
  };
}
