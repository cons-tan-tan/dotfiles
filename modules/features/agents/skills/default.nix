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
  flake-file.inputs.yomiyasu = {
    url = "github:nanaism/yomiyasu";
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
          commitProfiles =
            if skillSources ? commit then
              import ./_packages/commit-profiles {
                inherit pkgs;
                standard = skillSources.commit;
              }
            else
              null;
          deployTo =
            prefix:
            lib.mapAttrs' (name: source: lib.nameValuePair "${prefix}/${name}" { inherit source; }) (
              removeAttrs skillSources [ "commit" ]
            );
        in
        {
          imports = [ ./_interface/options.nix ];
          dotfiles.agentSkills.externalSkills = enabledDefinitions;
          dotfiles.agentSkills.commitProfiles = commitProfiles;
          home.file = deployTo ".claude/skills" // deployTo ".agents/skills";
        }
      )

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          config = lib.mkIf config.dotfiles.platform.windows.enable (
            let
              hasSkills = config.dotfiles.agentSkills.externalSkills != { };
              # Native Windows clients bypass the Unix adapters. Compose their
              # trees separately so they retain the standard commit skill.
              windowsTree =
                prefix:
                pkgs.linkFarm "windows-agent-skills" (
                  lib.mapAttrsToList (path: file: {
                    name = lib.removePrefix "${prefix}/" path;
                    path = file.source;
                  }) (lib.filterAttrs (path: file: file.enable && lib.hasPrefix "${prefix}/" path) config.home.file)
                  ++ lib.optional (config.dotfiles.agentSkills.commitProfiles != null) {
                    name = "commit";
                    path = config.dotfiles.agentSkills.commitProfiles.standard;
                  }
                );
            in
            lib.mkIf hasSkills {
              dotfiles.windows.staticResources.skills.trees = [
                {
                  source = toString (windowsTree ".claude/skills");
                  destination = ".claude/skills";
                  excludes = [ "ax/" ];
                }
                {
                  source = toString (windowsTree ".agents/skills");
                  destination = ".agents/skills";
                  excludes = [ "ax/" ];
                }
              ];
            }
          );
        }
      )

    ];
  };

  flake.modules.homeManager.agent-skills = {
    key = "modules/features/agents/skills/default.nix#homeManager.agent-skills";
    imports = [
      config.flake.modules.homeManager.agent-skills-external
      config.flake.modules.homeManager.agent-skills-local
      config.flake.modules.homeManager.agent-skills-consumer
    ];
  };
}
