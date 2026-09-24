{
  config,
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

  flake.modules.homeManager.agent-skills-external = {
    key = "modules/features/agents/skills/default.nix#homeManager.agent-skills-external";
    dotfiles.agentSkillContributions = entries "external" externalDefinitions;
  };

  flake.modules.homeManager.agent-skills-local = {
    key = "modules/features/agents/skills/default.nix#homeManager.agent-skills-local";
    dotfiles.agentSkillContributions = entries "local" localDefinitions;
  };

  flake.modules.homeManager.agent-skills-consumer = {
    key = "modules/features/agents/skills/default.nix#homeManager.agent-skills-consumer";
    imports = [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          aggregated = import (skillsLib + "/aggregate.nix") {
            inherit lib;
          } config.dotfiles.agentSkillContributions;
          # Evaluate predicates here so every deployment target shares the
          # same filtered definitions, including config-dependent skills.
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
        }
      )

      ({ config, lib, ... }: {
        config = lib.mkIf config.dotfiles.platform.windows.enable (
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
          }
        );
      })

    ];
  };

  flake.modules.homeManager.agent-skills = {
    key = "modules/features/agents/skills/default.nix#homeManager.agent-skills";
    imports = [
      config.flake.modules.homeManager.agent-skills-external
      config.flake.modules.homeManager.pptx-agent-skill
      config.flake.modules.homeManager.drawio-agent-skill
      config.flake.modules.homeManager.agent-skills-local
      config.flake.modules.homeManager.agent-skills-consumer
    ];
  };
}
