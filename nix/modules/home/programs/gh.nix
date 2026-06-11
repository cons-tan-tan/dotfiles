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

    # Windows companion (gh.exe) へのエイリアス反映は
    # modules/wsl/windows/gh.nix が行う。
    settings.aliases = (import ../../../lib/settings/gh.nix).aliases;
  };
}
