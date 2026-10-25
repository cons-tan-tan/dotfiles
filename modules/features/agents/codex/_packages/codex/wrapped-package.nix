{
  codex,
  commitProfiles ? null,
  lib,
  symlinkJoin,
  writeShellApplication,
}:
let
  # Pin CODEX_BIN to the upstream executable so nested wrappers cannot recurse.
  wrapper = writeShellApplication {
    name = "codex";
    text = ''
      CODEX_BIN=${lib.escapeShellArg "${codex}/bin/codex"}
      ${lib.optionalString (commitProfiles != null) ''
        COMMIT_PROFILE_SELECTOR=${lib.escapeShellArg (lib.getExe commitProfiles.selector)}
        COMMIT_PROFILE_ARTIFACTS=${lib.escapeShellArg (toString commitProfiles.artifacts)}
      ''}
      ${builtins.readFile ./codex-wrapper.sh}
    '';
  };
in
symlinkJoin {
  name = "codex-wrapped";
  paths = [ codex ];
  postBuild = ''
    rm "$out/bin/codex"
    ln -s ${wrapper}/bin/codex "$out/bin/codex"
  '';
  inherit (codex) meta;
}
