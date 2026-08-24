{
  features,
  inputs,
  ...
}:
{
  flake-file.inputs.gh-stack-src = {
    url = "github:github/gh-stack/v0.1.0";
    flake = false;
  };

  features.gh =
    { config, ... }:
    {
      name = "feature/gh";
      includes = [ features.git ];
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
            stack.view = true;
            api-get = true;
          };
        }
      ];
      agent-skills = [
        {
          name = "gh-stack";
          provenance = "external";
          definition.root = inputs.gh-stack-src.outPath + "/skills/gh-stack";
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
            pkgs.gh-stack
          ];
        };
      };
    };
}
