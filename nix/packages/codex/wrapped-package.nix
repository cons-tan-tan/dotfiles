{
  codex,
  herdrSkillPath,
  lib,
  symlinkJoin,
  writeShellApplication,
}:
let
  herdrSkillOverride = "skills.config=[{path=${builtins.toJSON herdrSkillPath},enabled=true}]";
  # CODEX_BIN は upstream の絶対パスを保持し、ラッパーを重ねても元の実行
  # ファイルを確実に呼び出せるようにする。
  wrapper = writeShellApplication {
    name = "codex";
    text = ''
      CODEX_BIN=${lib.escapeShellArg "${codex}/bin/codex"}
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
