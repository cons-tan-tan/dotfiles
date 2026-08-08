{
  features.cli-tool-jq =
    { config, ... }:
    {
      name = "feature/cli-tools/jq";
      cli-tools = [
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
      agent-command-policy = [
        {
          owner = config.name;
          policy.commands.jq = true;
        }
      ];
    };
}
