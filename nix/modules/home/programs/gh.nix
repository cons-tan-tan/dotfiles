{
  config,
  pkgs,
  lib,
  hostKind,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

  aliases = config.programs.gh.settings.aliases or { };

  setAliasCommands = lib.concatMapStringsSep "\n" (
    name:
    let
      value = aliases.${name};
    in
    ''run "$GH_EXE" alias set ${lib.escapeShellArg name} ${lib.escapeShellArg value} --clobber > /dev/null''
  ) (builtins.attrNames aliases);
in
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

  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsGhAliases = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GH_EXE="/mnt/c/Program Files/GitHub CLI/gh.exe"
      if [ ! -x "$GH_EXE" ]; then
        echo "deployWindowsGhAliases: $GH_EXE not found, skipping (run winget-apply first)" >&2
        exit 0
      fi
      ${setAliasCommands}
    '';
  };
}
