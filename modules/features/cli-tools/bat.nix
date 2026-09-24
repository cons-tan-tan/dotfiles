{
  flake.modules.homeManager.cli-tools = {
    key = "modules/features/cli-tools/bat.nix#homeManager.cli-tools";
    dotfiles.cliTools = [
      {
        id = "bat";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "bat";
        };
        winget = {
          packageId = "sharkdp.bat";
          description = "bat";
        };
      }
    ];
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/cli-tools/bat";
        policy.commands.bat = true;
      }
    ];
  };
}
