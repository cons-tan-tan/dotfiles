{ ... }:
{
  features.development-watchexec = {
    name = "feature/development/watchexec";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.watchexec ];
      };
  };
}
