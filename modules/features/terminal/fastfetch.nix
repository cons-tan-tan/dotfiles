{
  flake.modules.homeManager.terminal-fastfetch =
    { pkgs, ... }:
    {
      key = "modules/features/terminal/fastfetch.nix#homeManager.terminal-fastfetch";

      home.packages = [ pkgs.fastfetch ];
    };
}
