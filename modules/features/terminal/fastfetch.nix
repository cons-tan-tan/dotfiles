{
  features.terminal-fastfetch = {
    name = "feature/terminal/fastfetch";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.fastfetch ];
      };
  };
}
