{
  features.cli-tool-eza =
    { config, ... }:
    {
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
          owner = config.name;
          policy.commands.eza = true;
        }
      ];
    };
}
