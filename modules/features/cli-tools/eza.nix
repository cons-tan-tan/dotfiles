{
  flake.modules.homeManager.cli-tool-eza = {
    key = "modules/features/cli-tools/eza.nix#homeManager.cli-tool-eza";
    dotfiles.cliTools = [
      {
        id = "eza";
        nix = {
          route = "home-packages";
          nixpkgsAttr = "eza";
        };
        winget = {
          packageId = "eza-community.eza";
          description = "eza";
        };
      }
    ];
    dotfiles.agentCommandPolicyContributions = [
      {
        owner = "feature/cli-tools/eza";
        policy.commands.eza = true;
      }
    ];
  };
}
