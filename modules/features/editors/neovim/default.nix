{
  features.editors-neovim = {
    name = "feature/editors/neovim";
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.neovim ];
      };
  };
}
