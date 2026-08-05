{ ... }:
{
  features.cli-tool-jq = {
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
        source = "feature/cli-tools/jq";
        policy.commands.jq = true;
      }
    ];
  };
}
