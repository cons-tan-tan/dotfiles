# Windows companion: Windows 側 gh.exe に明示エイリアスを反映する。
# POSIX 側の `gh api-get` は Home Manager の gh extension で提供する。
{
  lib,
  ...
}:
let
  # Windows へ反映する alias は明示列挙する (programs.gh の全 alias を自動
  # 同期しない: Linux 専用コマンドを含む alias を誤って push しないため)。
  windowsAliases = { };

  setAliasCommands = lib.concatMapStringsSep "\n" (
    name:
    ''run "$GH_EXE" alias set ${lib.escapeShellArg name} ${
      lib.escapeShellArg windowsAliases.${name}
    } --clobber > /dev/null''
  ) (builtins.attrNames windowsAliases);
in
{
  # NOTE: activation 断片は単一スクリプトに連結されるため、ここで exit すると
  # 後続の activation まで止まる。スキップは if 分岐で表現すること。
  home.activation = lib.mkIf (windowsAliases != { }) {
    deployWindowsGhAliases = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      GH_EXE=$(command -v gh.exe || true)
      if [ -z "$GH_EXE" ]; then
        # WSL interop の Windows PATH が無効な環境向けの既定インストール先
        GH_EXE="/mnt/c/Program Files/GitHub CLI/gh.exe"
      fi
      if [ -x "$GH_EXE" ]; then
      ${setAliasCommands}
      else
        echo "deployWindowsGhAliases: gh.exe not found, skipping (run apply-winget first)" >&2
      fi
    '';
  };
}
