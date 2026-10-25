{
  claudeCode,
  herdrPlugin,
  lib,
  nodejs,
  symlinkJoin,
  writeShellApplication,
}:
let
  # Pin the base executable so wrappers added by consumers cannot recurse.
  wrapper = writeShellApplication {
    name = "claude";
    text = ''
      CLAUDE_BASE=${lib.escapeShellArg "${claudeCode}/bin/claude"}
      NODE_BIN=${lib.escapeShellArg "${nodejs}/bin"}
      HERDR_PLUGIN=${lib.escapeShellArg "${herdrPlugin}"}
      ${builtins.readFile ./claude-wrapper.sh}
    '';
  };
in
symlinkJoin {
  name = "claude-code-wrapped";
  paths = [ claudeCode ];
  postBuild = ''
    rm "$out/bin/claude"
    ln -s ${wrapper}/bin/claude "$out/bin/claude"
  '';
  # Home Manager selects personal plugins or the legacy wrapper by version.
  inherit (claudeCode) meta version;
}
