{ ... }:
{
  features.cli-tool-bat =
    { config, ... }:
    {
      name = "feature/cli-tools/bat";
      cli-tools = [
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
      agent-command-policy = [
        {
          owner = config.name;
          policy.commands.bat = true;
        }
      ];
    };
}
