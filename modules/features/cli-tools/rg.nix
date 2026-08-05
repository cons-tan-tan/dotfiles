{ ... }:
{
  features.cli-tool-rg = {
    name = "feature/cli-tools/rg";
    cli-tools = [
      {
        id = "rg";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "ripgrep";
        };
        winget = {
          packageId = "BurntSushi.ripgrep.MSVC";
          description = "ripgrep";
        };
      }
    ];
    agent-command-policy = [
      {
        source = "feature/cli-tools/rg";
        policy.commands.rg = true;
      }
    ];
  };
}
