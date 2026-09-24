{
  flake.modules.homeManager.cli-tools = {
    key = "modules/features/cli-tools/fzf.nix#homeManager.cli-tools";
    dotfiles.cliTools = [
      {
        id = "fzf";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "fzf";
        };
        winget = {
          packageId = "junegunn.fzf";
          description = "fzf";
        };
      }
    ];
  };
}
