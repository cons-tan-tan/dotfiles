{
  flake.modules.homeManager.cli-tool-jq = {
    key = "modules/features/cli-tools/jq.nix#homeManager.cli-tool-jq";
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
