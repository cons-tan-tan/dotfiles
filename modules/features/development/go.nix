{
  features.development-go = {
    name = "feature/development/go";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.go ];
      };
  };
}
