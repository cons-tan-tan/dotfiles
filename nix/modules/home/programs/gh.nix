{ pkgs, ... }:
{
  programs.gh = {
    enable = true;

    gitCredentialHelper.enable = true;

    extensions = [
      pkgs.dotfilesPackages.gh-api-get
      pkgs.gh-do
      pkgs.gh-poi
    ];

  };
}
