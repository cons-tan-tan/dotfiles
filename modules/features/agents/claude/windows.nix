{
  flake.modules.homeManager.agent-claude =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      payload = import ./_interface/payload.nix;
      settingsLib = import ./_lib/settings.nix {
        inherit lib;
        settings = config.dotfiles.claude.settings;
      };
      settingsValidator = import ./_interface/settings-validator.nix {
        inherit pkgs;
        schemaPin = import ./_interface/settings-schema.nix;
      };
      raw = (pkgs.formats.json { }).generate "claude-windows-settings.json" (
        settingsLib.mkSettings { forWindows = true; }
      );
      source = settingsValidator.validate "claude-windows-settings.json" raw;
    in
    {
      key = "modules/features/agents/claude/windows.nix#homeManager.agent-claude";
      config = lib.mkIf config.dotfiles.platform.windows.enable {
        dotfiles.windows = {
          deployments.claude = {
            directories = [ ".claude" ];
            files = [
              {
                source = toString source;
                destination = ".claude/settings.json";
              }
            ];
          };
          staticResources.claude.trees = [
            {
              source = "${config.dotfiles.platform.source}/${payload.repositoryRelative.commands}";
              destination = ".claude/commands";
            }
            {
              source = "${config.dotfiles.platform.source}/${payload.repositoryRelative.outputStyles}";
              destination = ".claude/output-styles";
            }
            {
              source = "${config.dotfiles.platform.source}/${payload.repositoryRelative.hooks}";
              destination = ".claude/hooks";
            }
          ];
        };
      };
    };
}
