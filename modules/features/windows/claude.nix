{ ... }:
{
  features.windows-claude = {
    name = "feature/windows/claude";
    windows =
      {
        config,
        lib,
        ...
      }:
      let
        pkgs = config._module.args.pkgs;
        settingsLib = import ../agents/_lib/settings/claude.nix { inherit lib; };
        settingsValidator = import ../agents/_lib/settings/claude-validator.nix { inherit pkgs; };
        raw = (pkgs.formats.json { }).generate "claude-windows-settings.json" (
          settingsLib.mkSettings { forWindows = true; }
        );
        source = settingsValidator.validate "claude-windows-settings.json" raw;
      in
      {
        dotfiles.windows.deployments.claude = {
          directories = [ ".claude" ];
          files = [
            {
              source = toString source;
              destination = ".claude/settings.json";
            }
          ];
        };
      };
  };
}
