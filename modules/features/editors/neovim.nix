{
  flake.modules.homeManager.editors-neovim =
    { pkgs, ... }:
    {
      key = "modules/features/editors/neovim.nix#homeManager.editors-neovim";

      home.packages = [ pkgs.neovim ];
    };
}
