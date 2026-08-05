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
