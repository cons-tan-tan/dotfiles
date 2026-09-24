{
  flake.modules.homeManager.cli-tool-bat = {
    key = "modules/features/cli-tools/bat.nix#homeManager.cli-tool-bat";
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
