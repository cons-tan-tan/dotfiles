{ ... }:
{
  features.terminal-yazi = {
    name = "feature/terminal/yazi";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.yazi ];
      };
  };
}
