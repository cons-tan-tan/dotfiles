{
  flake.modules.homeManager.cli-tools = {
    key = "modules/features/cli-tools/jq.nix#homeManager.cli-tools";
    dotfiles.cliTools = [
      {
        id = "jq";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "jq";
        };
        winget = {
          packageId = "jqlang.jq";
          description = "jq";
        };
      }
    ];
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/cli-tools/jq";
        policy.commands.jq = true;
      }
    ];
  };
}
