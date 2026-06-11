# Windows companion: Windows 側 gh.exe に programs.gh と同じエイリアスを反映
# する (gh の設定ファイルは hosts.yml と密結合なのでコマンドで設定する)。
{
  config,
  lib,
  ...
}:
let
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
  home.activation.deployWindowsGhAliases = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    GH_EXE="/mnt/c/Program Files/GitHub CLI/gh.exe"
    if [ ! -x "$GH_EXE" ]; then
      echo "deployWindowsGhAliases: $GH_EXE not found, skipping (run winget-apply first)" >&2
      exit 0
    fi
    ${setAliasCommands}
  '';
}
