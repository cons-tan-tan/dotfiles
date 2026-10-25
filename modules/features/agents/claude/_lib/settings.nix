{
  lib,
  settings,
  commandPolicy ? null,
}:
{
  mkSettings =
    {
      forWindows ? false,
      wslUserProfile ? null,
      guardCommand ? null,
    }:
    let
      commandPermissions =
        if forWindows then
          {
            allow = [ ];
            deny = [ ];
          }
        else if commandPolicy == null then
          throw "Claude settings require the merged agent command policy for non-Windows targets"
        else
          commandPolicy.mkClaudePermissions { };
    in
    settings
    // {
      env =
        settings.env
        // lib.optionalAttrs (wslUserProfile != null) {
          # Claude Code 2.1.212 otherwise queries USERPROFILE through PowerShell.
          # https://github.com/anthropics/claude-code/issues/619#issuecomment-4106944524
          USERPROFILE = wslUserProfile;
        };
      permissions =
        settings.permissions
        // {
          allow = settings.permissions.allow ++ lib.optionals (!forWindows) commandPermissions.allow;
        }
        // lib.optionalAttrs (!forWindows) (
          {
            inherit (commandPermissions) deny;
          }
          // lib.optionalAttrs (commandPermissions ? ask) { inherit (commandPermissions) ask; }
        );
      hooks.PreToolUse = lib.optionals (!forWindows && guardCommand != null) [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = guardCommand;
              timeout = 10;
            }
          ];
        }
      ];
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    };
}
