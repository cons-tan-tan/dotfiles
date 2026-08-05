{ features, ... }:
{
  features.source-control-gh = {
    name = "feature/source-control/gh";
    includes = [ features.source-control-git ];
    cli-tools = [
      {
        id = "gh";
        nix.route = "programs";
        winget = {
          packageId = "GitHub.cli";
          dependsOn = [ "git" ];
          description = "GitHub CLI";
        };
      }
    ];
    agent-command-policy = [
      {
        source = "feature/source-control/gh";
        policy.commands.gh = {
          issue = {
            list = true;
            view = true;
          };
          pr = {
            list = true;
            view = true;
            diff = true;
            checks = true;
          };
          run = {
            list = true;
            view = true;
          };
          repo = {
            clone = true;
            read-dir = true;
            read-file = true;
            view = true;
          };
          search = true;
          api-get = true;
        };
      }
    ];
    homeManager = { pkgs, ... }: {
      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = true;
        extensions = [
          pkgs.dotfilesPackages.gh-api-get
          pkgs.gh-do
          pkgs.gh-poi
        ];
      };
    };
  };
}
