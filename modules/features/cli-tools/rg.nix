{
  features.cli-tool-rg =
    { config, ... }:
    {
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
          owner = config.name;
          policy.commands.rg = true;
        }
      ];
    };
}
