{
  flake.modules.homeManager.cli-tools = {
    key = "modules/features/cli-tools/reuse.nix#homeManager.cli-tools";
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
