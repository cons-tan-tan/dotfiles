# skill (flake inputs + agents/skills/) を ~/.claude/skills と
# ~/.agents/skills へ配置する。
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

  inherit (import ./frontmatter.nix { inherit lib; })
    disableCodexImplicitInvocation
    disableModelInvocation
    filterFrontmatterFields
    ;

  # Upstream frontmatter is deny-by-default. Descriptive metadata is safe to
  # inherit globally; fields that alter tools, hooks, models, or invocation
  # require an explicit per-skill opt-in in sources.nix.
  defaultInheritedFrontmatterFields = [
    "name"
    "description"
    "license"
    "compatibility"
    "metadata"
    "hidden"
  ];

  # transform や追加ファイルが必要な skill はコピーを作る。無ければソースを
  # そのまま symlink する。
  mkSkillSource =
    name: skill:
    let
      disableAutomaticInvocation = skill.disableAutomaticInvocation or false;
      transform = skill.transform or lib.id;
      originalSkillMd = builtins.readFile (skill.root + "/SKILL.md");
      transformedSkillMd = transform originalSkillMd;
      inheritedFrontmatterFields =
        defaultInheritedFrontmatterFields ++ (skill.additionalInheritedFrontmatterFields or [ ]);
      filteredSkillMd = filterFrontmatterFields inheritedFrontmatterFields transformedSkillMd;
      skillMd = (if disableAutomaticInvocation then disableModelInvocation else lib.id) (filteredSkillMd);
      sourceOpenaiYamlPath = skill.root + "/agents/openai.yaml";
      openaiYaml = disableCodexImplicitInvocation (
        if builtins.pathExists sourceOpenaiYamlPath then builtins.readFile sourceOpenaiYamlPath else ""
      );
      frontmatterWasFiltered = filteredSkillMd != transformedSkillMd;
    in
    if (skill ? transform) || disableAutomaticInvocation || frontmatterWasFiltered then
      pkgs.runCommandLocal "skill-${name}"
        (
          {
            inherit skillMd;
            passAsFile = [ "skillMd" ] ++ lib.optionals disableAutomaticInvocation [ "openaiYaml" ];
          }
          // lib.optionalAttrs disableAutomaticInvocation { inherit openaiYaml; }
        )
        ''
          cp -rL --no-preserve=mode ${skill.root} $out
          cp "$skillMdPath" "$out/SKILL.md"
          ${lib.optionalString disableAutomaticInvocation ''
            mkdir -p "$out/agents"
            cp "$openaiYamlPath" "$out/agents/openai.yaml"
          ''}
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
