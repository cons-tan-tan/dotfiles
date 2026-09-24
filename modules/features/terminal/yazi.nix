{
  flake.modules.homeManager.terminal-yazi =
    { pkgs, ... }:
    {
      key = "modules/features/terminal/yazi.nix#homeManager.terminal-yazi";

      home.packages = [ pkgs.yazi ];
    };
}
