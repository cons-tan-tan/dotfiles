{
  codex,
  herdrSkillPath,
  lib,
  writeShellApplication,
}:
let
  herdrSkillOverride = "skills.config=[{path=${builtins.toJSON herdrSkillPath},enabled=true}]";
in
writeShellApplication {
  name = "codex";
  text = ''
    CODEX_BIN=${lib.escapeShellArg "${codex}/bin/codex"}
    HERDR_SKILL_OVERRIDE=${lib.escapeShellArg herdrSkillOverride}
    ${builtins.readFile ./codex-wrapper.sh}
  '';
}
