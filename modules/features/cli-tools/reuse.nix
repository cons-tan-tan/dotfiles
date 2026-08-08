{
  features.cli-tool-reuse = {
    name = "feature/cli-tools/reuse";
    cli-tools = [
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
