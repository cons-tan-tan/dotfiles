{
  flake.modules.homeManager.cli-tools = {
    key = "modules/features/cli-tools/rg.nix#homeManager.cli-tools";
    dotfiles.cliTools = [
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
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/cli-tools/rg";
        policy.commands.rg = true;
      }
    ];
  };
}
