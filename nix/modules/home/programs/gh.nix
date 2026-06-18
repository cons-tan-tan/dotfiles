{
  pkgs,
  ...
}:
let
  ghApiGetBin = pkgs.writeShellApplication {
    name = "gh-api-get";
    runtimeInputs = [ pkgs.gh ];
    text = builtins.readFile ./gh-api-get.sh;
  };

  ghApiGet =
    # gh extension lookup expects the executable at the extension root, while
    # writeShellApplication installs it under bin/.
    pkgs.symlinkJoin {
      name = "gh-api-get";
      paths = [ ghApiGetBin ];
      postBuild = ''
        ln -s "$out/bin/gh-api-get" "$out/gh-api-get"
      '';
    }
    // {
      # Home Manager names gh extension directories from pname.
      pname = "gh-api-get";
    };
in
{
  programs.gh = {
    enable = true;

    gitCredentialHelper.enable = true;

    extensions = [
      ghApiGet
      pkgs.gh-do
      pkgs.gh-poi
    ];

    # Windows companion (gh.exe) へのエイリアス反映は
    # modules/wsl/windows/gh.nix が行う。
    settings.aliases = (import ../../../lib/settings/gh.nix).aliases;
  };
}
