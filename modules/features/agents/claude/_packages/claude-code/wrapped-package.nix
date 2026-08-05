{
  claudeCode,
  herdrPlugin,
  lib,
  nodejs,
  symlinkJoin,
  writeShellApplication,
}:
let
  # Home Manager also wraps Claude Code when plugins are enabled, so the
  # wrapper keeps an absolute reference to its base executable for safe
  # composition.
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
  inherit (claudeCode) meta;
}
