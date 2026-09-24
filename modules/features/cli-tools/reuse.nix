{
  flake.modules.homeManager.cli-tool-reuse = {
    key = "modules/features/cli-tools/reuse.nix#homeManager.cli-tool-reuse";
    dotfiles.cliTools = [
      {
        id = "reuse";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "reuse";
        };
      }
    ];
  };
}
