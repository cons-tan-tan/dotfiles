# skill (flake inputs + agents/skills/) を ~/.claude/skills と
# ~/.agents/skills へ配置する。
#
# NOTE: 以前は agent-skills-nix (flake input) を使っていたが、同モジュールは
# ソースの safe-copy derivation を eval 時に readFile する (IFD) ため、異種
# プラットフォーム構成の評価 (nix flake check 等) を壊す。必要な機能は
# 「skill ディレクトリを集め、SKILL.md を変換して配置する」だけなので自前で
# 実装する。eval 時に読むのは flake input / リポジトリ内の純パスのみ。
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  externalSkills = config.dotfiles.agentSkills.externalSkills;
  localSkillsDir = ../../../../agents/skills;
  localSkills = lib.mapAttrs (name: _: { root = localSkillsDir + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir localSkillsDir)
  );
  inherit (import ./policy.nix { inherit lib; })
    defaultInheritedFrontmatterFields
    mergeSkillDefinitions
    ;
  skills = mergeSkillDefinitions externalSkills localSkills;

  inherit (import ./skill-policy.nix { inherit lib; })
    prepareSkill
    validateSkillDefinition
    ;
  inherit (import ./codex-invocation-policy.nix { inherit lib; })
    disableCodexImplicitInvocation
    ;

  # customization や frontmatter filtering が必要な skill はコピーを作る。
  # 変更が無ければソースをそのまま symlink する。
  mkSkillSource =
    name: skill:
    let
      definition = validateSkillDefinition name skill;
      inherit (definition) root customization;
      originalSkillMd = builtins.readFile (root + "/SKILL.md");
      prepared = prepareSkill {
        inherit name root customization;
        defaultInheritedFields = defaultInheritedFrontmatterFields;
        requireExplicitFieldDecisions = builtins.hasAttr name externalSkills;
      } originalSkillMd;
      inherit (prepared) skillMd disableAutomaticInvocation;
      sourceOpenaiYamlPath = root + "/agents/openai.yaml";
      openaiYaml = disableCodexImplicitInvocation (
        if builtins.pathExists sourceOpenaiYamlPath then builtins.readFile sourceOpenaiYamlPath else ""
      );
    in
    if definition.hasCustomization || prepared.frontmatterWasFiltered then
      pkgs.runCommandLocal "skill-${name}"
        (
          {
            inherit skillMd;
            passAsFile = [ "skillMd" ] ++ lib.optionals disableAutomaticInvocation [ "openaiYaml" ];
          }
          // lib.optionalAttrs disableAutomaticInvocation { inherit openaiYaml; }
        )
        ''
          cp -rL --no-preserve=mode ${root} $out
          cp "$skillMdPath" "$out/SKILL.md"
          ${lib.optionalString disableAutomaticInvocation ''
            mkdir -p "$out/agents"
            cp "$openaiYamlPath" "$out/agents/openai.yaml"
          ''}
        ''
    else
      root;

  skillSources = lib.mapAttrs mkSkillSource skills;

  deployTo =
    prefix:
    lib.mapAttrs' (
      name: source: lib.nameValuePair "${prefix}/${name}" { inherit source; }
    ) skillSources;
in
{
  imports = [
    ./options.nix
    ./sources.nix
  ];

  home.file = deployTo ".claude/skills" // deployTo ".agents/skills";
}
