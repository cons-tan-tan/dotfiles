{
  pkgs,
  ...
}:
{
  programs.gh = {
    enable = true;

    gitCredentialHelper.enable = true;

    extensions = [
      pkgs.gh-do
      pkgs.gh-poi
    ];

    settings.aliases = {
      api-get = ''!gh api "$@" --method GET'';
    };
  };
}
