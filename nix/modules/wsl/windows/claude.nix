# Windows companion: Windows 側 Claude Code の settings.json を書き出す。
# Windows は hcomと共通command policyの対象外なので、生成物とのマージは不要。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  settingsLib = import ../../../lib/settings/claude.nix { inherit lib; };
  settingsValidator = import ../../../lib/mk-claude-settings-validator.nix { inherit pkgs; };
  deploy = import ./deploy.nix { inherit lib; };

  windowsHomedir = config.my.windows.homedir;

  windowsSettingsRaw = (pkgs.formats.json { }).generate "claude-windows-settings.json" (
    settingsLib.mkSettings {
      forWindows = true;
    }
  );

  windowsSettingsFile = settingsValidator.validate "claude-windows-settings.json" windowsSettingsRaw;
in
{
  home.activation.deployWindowsClaudeSettings = deploy.mkDeployActivation {
    dirs = [ "${windowsHomedir}/.claude" ];
    files = [
      {
        src = windowsSettingsFile;
        dst = "${windowsHomedir}/.claude/settings.json";
      }
    ];
  };
}
