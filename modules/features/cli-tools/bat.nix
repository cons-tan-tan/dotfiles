{ ... }:
{
  features.cli-tool-bat = {
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
        source = "feature/cli-tools/bat";
        policy.commands.bat = true;
      }
    ];
  };
}
