{ features, ... }:
{
  features.source-control-gh = {
    name = "feature/source-control/gh";
    includes = [ features.source-control-git ];
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
