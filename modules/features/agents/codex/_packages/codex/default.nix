{
  callPackage,
  codex,
}:
let
  updater = callPackage ../../_scripts/update-app.nix { };
in
{
  appUpdater = updater.overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      updateScript = "${updater}/bin/update-codex-app";
      updateScriptName = "codex-app";
      updateScriptDescription = "Update the pinned Codex desktop app from its appcast";
    };
  });

  mkWrappedPackage =
    { herdrSkillPath }:
    callPackage ./wrapped-package.nix {
      inherit codex herdrSkillPath;
    };
}
