# Agent skills deployment for Claude Code and other agents.
#
# Skills (external flake inputs + local agents/skills/) are bundled and
# symlinked into ~/.claude/skills and ~/.agents/skills.
#
# NOTE: 以前は agent-skills-nix (flake input) を使っていたが、同モジュールは
# ソースの safe-copy derivation を eval 時に readFile する (IFD) ため、異種
# プラットフォーム構成の評価 (nix flake check 等) を壊す。必要な機能は
# 「skill ディレクトリを集め、SKILL.md を変換して配置する」だけなので自前で
# 実装する。eval 時に読むのは flake input / リポジトリ内の純パスのみ。
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  skills = import ./sources.nix { inherit lib inputs; };

  # transform がある skill は SKILL.md を差し替えたコピーを作る。無ければ
  # ソースをそのまま symlink する。
  mkSkillSource =
    name: skill:
    if skill ? transform then
      pkgs.runCommandLocal "skill-${name}"
        {
          skillMd = skill.transform (builtins.readFile (skill.root + "/SKILL.md"));
          passAsFile = [ "skillMd" ];
        }
        ''
          cp -rL --no-preserve=mode ${skill.root} $out
          cp "$skillMdPath" "$out/SKILL.md"
        ''
    else
      skill.root;

  skillSources = lib.mapAttrs mkSkillSource skills;

  deployTo =
    prefix:
    lib.mapAttrs' (
      name: source: lib.nameValuePair "${prefix}/${name}" { inherit source; }
    ) skillSources;
in
{
  home.file = deployTo ".claude/skills" // deployTo ".agents/skills";
}
