{ features, ... }:
{
  features.source-control-gh =
    { config, ... }:
    {
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
          owner = config.name;
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
              download = true;
              list = true;
              view = true;
              watch = true;
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
