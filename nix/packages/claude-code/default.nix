{
  bash,
  claudeCode,
  herdrPlugin,
  nodejs,
  symlinkJoin,
}:
# Home Manager also wraps Claude Code when plugins are enabled, so this package
# keeps an absolute reference to its base executable for safe composition.
symlinkJoin {
  name = "claude-code-wrapped";
  paths = [ claudeCode ];
  postBuild = ''
    mv "$out/bin/claude" "$out/bin/.claude-wrapped-base"
    cat >"$out/bin/claude" <<'EOF'
    #! ${bash}/bin/bash -e
    CLAUDE_BASE="@out@/bin/.claude-wrapped-base"
    NODE_BIN=${nodejs}/bin
    HERDR_PLUGIN=${herdrPlugin}
    ${builtins.readFile ./claude-wrapper.sh}
    EOF
    substituteInPlace "$out/bin/claude" --replace-fail @out@ "$out"
    chmod +x "$out/bin/claude"
  '';
  inherit (claudeCode) meta;
}
