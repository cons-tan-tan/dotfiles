{
  codex,
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
