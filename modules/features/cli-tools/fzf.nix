{ ... }:
{
  features.cli-tool-fzf = {
    name = "feature/cli-tools/fzf";
    cli-tools = [
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
