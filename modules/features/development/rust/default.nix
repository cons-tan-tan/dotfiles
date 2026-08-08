{
  features.development-rust = {
    name = "feature/development/rust";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.rustup ];
      };
  };
}
