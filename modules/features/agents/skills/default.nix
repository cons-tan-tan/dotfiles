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
        mkSkillSource = import (skillsLib + "/mk-skill-source.nix") { inherit pkgs; };

        skillSources = lib.mapAttrs (
          name: definition:
          mkSkillSource {
            inherit definition name;
            provenance = aggregated.provenance.${name};
          }
        ) skills;
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
