{ ... }:
{
  features.cli-tool-eza = {
    name = "feature/cli-tools/eza";
    cli-tools = [
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
    agent-command-policy = [
      {
        source = "feature/cli-tools/eza";
        policy.commands.eza = true;
      }
    ];
  };
}
