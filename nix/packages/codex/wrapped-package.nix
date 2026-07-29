{
  codex,
  fd,
  herdrSkillPath,
  lib,
  symlinkJoin,
  writeText,
  writeShellApplication,
}:
let
  agentFdWrapper = import ../agent-fd-wrapper {
    inherit
      fd
      lib
      writeText
      writeShellApplication
      ;
  };
  herdrSkillOverride = "skills.config=[{path=${builtins.toJSON herdrSkillPath},enabled=true}]";
  # CODEX_BIN は upstream の絶対パスを保持し、ラッパーを重ねても元の実行
  # ファイルを確実に呼び出せるようにする。
  wrapper = writeShellApplication {
    name = "codex";
    text = ''
      CODEX_BIN=${lib.escapeShellArg "${codex}/bin/codex"}
      FD_WRAPPER_DIR=${lib.escapeShellArg "${agentFdWrapper}/bin"}
      HERDR_SKILL_OVERRIDE=${lib.escapeShellArg herdrSkillOverride}
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
