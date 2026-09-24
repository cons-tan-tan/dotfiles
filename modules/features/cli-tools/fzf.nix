{
  flake.modules.homeManager.cli-tool-fzf = {
    key = "modules/features/cli-tools/fzf.nix#homeManager.cli-tool-fzf";
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
