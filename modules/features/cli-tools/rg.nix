{
  flake.modules.homeManager.cli-tool-rg = {
    key = "modules/features/cli-tools/rg.nix#homeManager.cli-tool-rg";
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
