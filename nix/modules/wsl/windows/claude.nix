# Windows companion: Windows 側 Claude Code の settings.json を書き出す。
# Windows には hcom (linux/darwin バイナリ) が無いので gh-api guard のみで、
# hcom 生成物とのマージは不要。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  settingsLib = import ../../../lib/settings/claude.nix { inherit lib; };

  windowsHomedir = config.my.windows.homedir;

  windowsSettingsFile = (pkgs.formats.json { }).generate "claude-windows-settings.json" (
    settingsLib.mkSettings {
      forWindows = true;
      windowsUsername = config.my.windows.username;
    }
  );
in
{
  home.activation.deployWindowsClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p ${windowsHomedir}/.claude
    run install -m644 ${windowsSettingsFile} ${windowsHomedir}/.claude/settings.json
  '';
}
