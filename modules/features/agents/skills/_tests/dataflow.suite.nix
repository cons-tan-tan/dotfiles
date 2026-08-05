{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../../..,
}:
let
  skillsRoot = repoRoot + "/modules/features/agents/skills";
  aggregateSkills = import (skillsRoot + "/_lib/aggregate.nix") { inherit lib; };

  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (skillsRoot + "/quirk.nix")
  ];

  evalTest =
    module:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        inputs.den.flakeModules.denTest
        { denTest.imports = testImports; }
        (
          { denTest, ... }:
          {
            options.result = lib.mkOption { type = lib.types.raw; };
            config.result = denTest module;
          }
        )
      ];
    }).config.result;

  skillsSchemaConsumer = {
    homeManager =
      {
        agent-skills,
        ...
      }:
      let
        aggregated = aggregateSkills agent-skills;
      in
      {
        imports = [ (skillsRoot + "/_interface/options.nix") ];
        dotfiles.agentSkills.externalSkills = aggregated.definitions;
        home.sessionVariables.AGENT_SKILL_PROVENANCE = builtins.toJSON aggregated.provenance;
      };
  };

  baseHome =
    { lib, ... }:
    {
      den.default.homeManager.home = {
        username = "test";
        homeDirectory = lib.mkForce "/home/test";
        stateVersion = "25.11";
      };
    };

  tests = {
    testSkillQuirkMergesProducersIndependentlyOfIncludeOrder = evalTest (
      {
        den,
        features,
        pinguHm,
        tuxHm,
        ...
      }:
      {
        imports = [
          baseHome
          (skillsRoot + "/default.nix")
        ];
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };
        den.aspects.skills-external.agent-skills = [
          {
            name = "external";
            definition.root = repoRoot + "/agents/skills/missing-tools";
            provenance = "external";
          }
        ];
        den.aspects.skills-local.agent-skills = [
          {
            name = "local";
            definition.root = repoRoot + "/agents/skills/commit";
            provenance = "local";
          }
        ];
        den.aspects.tux.includes = [
          den.aspects.skills-local
          features.agent-skills-consumer
          den.aspects.skills-external
        ];
        den.aspects.pingu.includes = [ features.agent-skills-consumer ];

        expr = {
          tux = {
            names = builtins.attrNames tuxHm.dotfiles.agentSkills.externalSkills;
            claude = {
              external = tuxHm.home.file ? ".claude/skills/external";
              local = tuxHm.home.file ? ".claude/skills/local";
            };
            agents = {
              external = tuxHm.home.file ? ".agents/skills/external";
              local = tuxHm.home.file ? ".agents/skills/local";
            };
          };
          pingu = {
            names = builtins.attrNames pinguHm.dotfiles.agentSkills.externalSkills;
            leaked = pinguHm.home.file ? ".agents/skills/external";
          };
        };
        expected = {
          tux = {
            names = [
              "external"
              "local"
            ];
            claude = {
              external = true;
              local = true;
            };
            agents = {
              external = true;
              local = true;
            };
          };
          pingu = {
            names = [ ];
            leaked = false;
          };
        };
      }
    );
  };

  duplicateSkillsModule =
    { config, den, ... }:
    {
      imports = [ baseHome ];
      den.homes.x86_64-linux.tux = { };
      den.aspects.skills-consumer = skillsSchemaConsumer;
      den.aspects.skills-a.agent-skills = [
        {
          name = "duplicate";
          definition.root = ./.;
          provenance = "local";
        }
      ];
      den.aspects.skills-b.agent-skills = [
        {
          name = "duplicate";
          definition.root = ./.;
          provenance = "external";
        }
      ];
      den.aspects.tux.includes = [
        den.aspects.skills-a
        den.aspects.skills-b
        den.aspects.skills-consumer
      ];
      expr = builtins.attrNames config.flake.homeConfigurations.tux.config.dotfiles.agentSkills.externalSkills;
    };

  failureCases = {
    duplicateSkillNames = {
      expression = (evalTest duplicateSkillsModule).expr;
      expectedFragments = [ "agent skills contain duplicate names: duplicate" ];
    };
    invalidSkillProvenance = {
      expression =
        (evalTest (
          { config, den, ... }:
          {
            imports = [ baseHome ];
            den.homes.x86_64-linux.tux = { };
            den.aspects.skills-consumer = skillsSchemaConsumer;
            den.aspects.skills-invalid.agent-skills = [
              {
                name = "invalid";
                definition.root = ./.;
                provenance = "unknown";
              }
            ];
            den.aspects.tux.includes = [
              den.aspects.skills-invalid
              den.aspects.skills-consumer
            ];
            expr = builtins.deepSeq (config.flake.homeConfigurations.tux.config.dotfiles.agentSkills.externalSkills) true;
          }
        )).expr;
      expectedFragments = [ "agent skill quirk entry has an invalid provenance" ];
    };
    invalidSkillEnablePredicate = {
      expression = builtins.deepSeq (aggregateSkills [
        {
          name = "invalid";
          definition.root = ./.;
          provenance = "local";
          enable = true;
        }
      ]) true;
      expectedFragments = [ "agent skill quirk entry enable predicate must be a function" ];
    };
    nonBooleanSkillEnablePredicate = {
      expression =
        (aggregateSkills [
          {
            name = "invalid";
            definition.root = ./.;
            provenance = "local";
            enable = _: "yes";
          }
        ]).enablePredicates.invalid
          { };
      expectedFragments = [ "agent skill quirk entry enable predicate must return a boolean" ];
    };
    invalidSkillDefinition = {
      expression =
        (evalTest (
          { config, den, ... }:
          {
            imports = [ baseHome ];
            den.homes.x86_64-linux.tux = { };
            den.aspects.skills-consumer = skillsSchemaConsumer;
            den.aspects.skills-invalid.agent-skills = [
              {
                name = "invalid";
                definition = {
                  root = ./.;
                  unexpected = true;
                };
                provenance = "local";
              }
            ];
            den.aspects.tux.includes = [
              den.aspects.skills-invalid
              den.aspects.skills-consumer
            ];
            expr = builtins.deepSeq (config.flake.homeConfigurations.tux.config.dotfiles.agentSkills.externalSkills) true;
          }
        )).expr;
      expectedFragments = [ "dotfiles.agentSkills.externalSkills.invalid.unexpected" ];
    };
    derivationSkillRoot = {
      expression =
        (evalTest (
          {
            config,
            den,
            inputs,
            ...
          }:
          let
            generatedSkill = inputs.nixpkgs.legacyPackages.x86_64-linux.writeTextDir "SKILL.md" "# generated";
          in
          {
            imports = [ baseHome ];
            den.homes.x86_64-linux.tux = { };
            den.aspects.skills-consumer = skillsSchemaConsumer;
            den.aspects.skills-generated.agent-skills = [
              {
                name = "generated";
                definition.root = "${generatedSkill}";
                provenance = "local";
              }
            ];
            den.aspects.tux.includes = [
              den.aspects.skills-generated
              den.aspects.skills-consumer
            ];
            expr = builtins.deepSeq (config.flake.homeConfigurations.tux.config.dotfiles.agentSkills.externalSkills) true;
          }
        )).expr;
      expectedFragments = [
        "agent skill roots must be repository or flake input paths, not derivation outputs"
      ];
    };
  };
in
if caseName == null then
  {
    inherit failureCases tests;
  }
else
  failureCases.${caseName}.expression
