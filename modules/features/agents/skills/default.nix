{
  features,
  inputs,
  lib,
  ...
}:
let
  skillsLib = ./_lib;
  localSkillsDir = (import ./_interface/payload.nix).localSkillsRoot;
  externalDefinitions = import ./_data/sources.nix { inherit inputs; };
  localDefinitions = lib.mapAttrs (name: _: { root = localSkillsDir + "/${name}"; }) (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir localSkillsDir)
  );
  entries =
    provenance: definitions:
    lib.mapAttrsToList (name: definition: {
      inherit definition name provenance;
    }) definitions;
in
{
  flake-file.inputs.anthropic-skills = {
    url = "github:anthropics/skills";
    flake = false;
  };
  flake-file.inputs.improve-skill = {
    url = "github:shadcn/improve";
    flake = false;
  };

  features.agent-skills-external = {
    name = "feature/agents/skills/external";
    agent-skills = entries "external" externalDefinitions;
  };

  features.agent-skills-local = {
    name = "feature/agents/skills/local";
    agent-skills = entries "local" localDefinitions;
  };

  features.agent-skills-consumer = {
    name = "feature/agents/skills/consumer";
    homeManager =
      {
        agent-skills,
        config,
        lib,
        pkgs,
        ...
      }:
      let
        aggregated = import (skillsLib + "/aggregate.nix") { inherit lib; } agent-skills;
        # Producers cannot see the final Home Manager option values. Keep
        # predicate evaluation here so every deployment target uses one filter.
        enabledDefinitions = lib.filterAttrs (
          name: _: aggregated.enablePredicates.${name} config
        ) aggregated.definitions;
        skills = config.dotfiles.agentSkills.externalSkills;
        inherit (import ./_data/policy.nix { inherit lib; })
          defaultInheritedFrontmatterFields
          ;
        inherit (import (skillsLib + "/skill-policy.nix") { inherit lib; })
          prepareSkill
          validateSkillDefinition
          ;
        inherit (import (skillsLib + "/codex-invocation-policy.nix") { inherit lib; })
          disableCodexImplicitInvocation
          ;

        mkSkillSource =
          name: skill:
          let
            definition = validateSkillDefinition name skill;
            inherit (definition) root customization;
            originalSkillMd = builtins.readFile (root + "/SKILL.md");
            prepared = prepareSkill {
              inherit name root customization;
              defaultInheritedFields = defaultInheritedFrontmatterFields;
              requireExplicitFieldDecisions = aggregated.provenance.${name} != "local";
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
        imports = [ ./_interface/options.nix ];
        dotfiles.agentSkills.externalSkills = enabledDefinitions;
        home.file = deployTo ".claude/skills" // deployTo ".agents/skills";
      };
    windows =
      { config, lib, ... }:
      let
        hasSkills = config.dotfiles.agentSkills.externalSkills != { };
      in
      lib.mkIf hasSkills {
        dotfiles.windows.staticResources.skills.trees = [
          {
            source = "${config.home.homeDirectory}/.claude/skills";
            destination = ".claude/skills";
            excludes = [ "ax/" ];
          }
          {
            source = "${config.home.homeDirectory}/.agents/skills";
            destination = ".agents/skills";
            excludes = [ "ax/" ];
          }
        ];
      };
  };

  features.agent-skills = {
    name = "feature/agents/skills";
    includes = [
      features.agent-skills-external
      features.pptx-agent-skill
      features.drawio-agent-skill
      features.agent-skills-local
      features.agent-skills-consumer
    ];
  };
}
