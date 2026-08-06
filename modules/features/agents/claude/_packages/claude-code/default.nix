{
  callPackage,
  claudeCode,
  herdrPlugin,
}:
let
  updater = callPackage ../../_scripts/update-settings-schema.nix { };
in
{
  package =
    (callPackage ./wrapped-package.nix {
      inherit claudeCode herdrPlugin;
    }).overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          updateScript = "${updater}/bin/update-claude-settings-schema";
          updateScriptName = "claude-code-settings-schema";
          updateScriptDescription = "Refresh the pinned Claude Code settings schema";
        };
      });
}
