{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../..,
}:
let
  agentsRoot = repoRoot + "/modules/features/agents";
  aggregateSkills = import (agentsRoot + "/_lib/skills/aggregate.nix") { inherit lib; };

  testImports = lib.optional (inputs ? flake-parts) inputs.den.flakeOutputs.flake ++ [
    (inputs.den.namespace "features" false)
    {
      options.flake-file = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    }
    (repoRoot + "/modules/classes/agent-command-policy.nix")
    (repoRoot + "/modules/quirks/agent-skills.nix")
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
        imports = [ (agentsRoot + "/_lib/skills/options.nix") ];
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
    testCommandPolicyMergesProducersAndKeepsUserScopesIsolated = evalTest (
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
          (agentsRoot + "/base.nix")
        ];
        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.policy-alpha.agentCommandPolicy.commands.alpha = true;
        den.aspects.policy-beta.agentCommandPolicy.commands.beta = false;
        den.aspects.tux = {
          includes = [
            features.agents-base
            den.aspects.policy-alpha
            den.aspects.policy-beta
          ];
        };
        den.aspects.pingu = {
          includes = [
            features.agents-base
          ];
          agentCommandPolicy.commands.pingu = true;
        };

        expr = {
          tux = {
            inherit (tuxHm.dotfiles.agentCommandPolicy.commands) alpha beta;
            compiledSchema = tuxHm.dotfiles.agentCommandPolicyCompiled.guardPolicy.schemaVersion;
            pingu = tuxHm.dotfiles.agentCommandPolicy.commands.pingu or null;
          };
          pingu = {
            inherit (pinguHm.dotfiles.agentCommandPolicy.commands) pingu;
            alpha = pinguHm.dotfiles.agentCommandPolicy.commands.alpha or null;
            compiledSchema = pinguHm.dotfiles.agentCommandPolicyCompiled.guardPolicy.schemaVersion;
          };
        };
        expected = {
          tux = {
            alpha = true;
            beta = false;
            compiledSchema = 2;
            pingu = null;
          };
          pingu = {
            alpha = null;
            compiledSchema = 2;
            pingu = true;
          };
        };
      }
    );

    testCommandPolicyReachesStandaloneHomeScope = evalTest (
      {
        config,
        features,
        ...
      }:
      {
        imports = [
          baseHome
          (agentsRoot + "/base.nix")
        ];
        den.homes.x86_64-linux.tux = { };
        den.aspects.tux = {
          includes = [
            features.agents-base
          ];
          agentCommandPolicy.commands.standalone = true;
        };

        expr = {
          inherit (config.flake.homeConfigurations.tux.config.dotfiles.agentCommandPolicy.commands)
            standalone
            ;
          compiledSchema =
            config.flake.homeConfigurations.tux.config.dotfiles.agentCommandPolicyCompiled.guardPolicy.schemaVersion;
        };
        expected = {
          standalone = true;
          compiledSchema = 2;
        };
      }
    );

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
          (agentsRoot + "/skills.nix")
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

    testHcomOptionControlsAllObservableArtifacts = evalTest (
      {
        config,
        features,
        ...
      }:
      let
        overlayPlan = import (repoRoot + "/nix/lib/mk-overlays.nix") { inherit inputs; } "x86_64-linux";
        observe =
          name:
          let
            home = config.flake.homeConfigurations.${name}.config;
            hcom = home.dotfiles.agentIntegrations.hcom;
          in
          {
            enabled = home.dotfiles.hcom.enable;
            integration = if hcom == null then "absent" else "present";
            package = if hcom != null && lib.elem hcom.package home.home.packages then "present" else "absent";
            skills = {
              agents = home.home.file ? ".agents/skills/hcom-agent-messaging";
              claude = home.home.file ? ".claude/skills/hcom-agent-messaging";
            };
            claudeSettings = toString home.home.file.".claude/settings.json".source;
            codexHooks = toString home.home.file.".codex/hooks.json".source;
            activation = {
              claudeBeforeCheckLinkTargets = lib.elem "checkLinkTargets" home.home.activation.claudeHooksDirectoryMigration.before;
              codexAfterLinkGeneration = lib.elem "linkGeneration" home.home.activation.codexHooksConfig.after;
            };
          };
        plain = observe "plain";
        hcom = observe "hcom";
      in
      {
        imports = [
          baseHome
          (agentsRoot + "/base.nix")
          (agentsRoot + "/claude.nix")
          (agentsRoot + "/codex.nix")
          (agentsRoot + "/guidance.nix")
          (agentsRoot + "/herdr.nix")
          (agentsRoot + "/hunk.nix")
          (agentsRoot + "/opencode.nix")
          (agentsRoot + "/pi.nix")
          (agentsRoot + "/skills.nix")
          (agentsRoot + "/hcom.nix")
        ];
        den.default.homeManager = {
          dotfiles.agentEnvironment = {
            environment = "linux";
            source = toString repoRoot;
          };
          nixpkgs.overlays = overlayPlan.overlays;
        };
        den.homes.x86_64-linux = {
          plain = { };
          hcom = { };
        };
        den.aspects.plain.includes = [ features.agents-default ];
        den.aspects.hcom = {
          includes = [ features.agents-default ];
          homeManager.dotfiles.hcom.enable = true;
        };

        expr = {
          plain = removeAttrs plain [
            "claudeSettings"
            "codexHooks"
          ];
          hcom = removeAttrs hcom [
            "claudeSettings"
            "codexHooks"
          ];
          consumers = {
            claudeSettingsDiffer = plain.claudeSettings != hcom.claudeSettings;
            codexHooksDiffer = plain.codexHooks != hcom.codexHooks;
          };
        };
        expected = {
          plain = {
            enabled = false;
            integration = "absent";
            package = "absent";
            skills = {
              agents = false;
              claude = false;
            };
            activation = {
              claudeBeforeCheckLinkTargets = true;
              codexAfterLinkGeneration = true;
            };
          };
          hcom = {
            enabled = true;
            integration = "present";
            package = "present";
            skills = {
              agents = true;
              claude = true;
            };
            activation = {
              claudeBeforeCheckLinkTargets = true;
              codexAfterLinkGeneration = true;
            };
          };
          consumers = {
            claudeSettingsDiffer = true;
            codexHooksDiffer = true;
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
    unknownCommandPolicyOption = {
      expression =
        (evalTest (
          {
            config,
            features,
            ...
          }:
          {
            imports = [
              baseHome
              (agentsRoot + "/base.nix")
            ];
            den.homes.x86_64-linux.tux = { };
            den.aspects.tux = {
              includes = [ features.agents-base ];
              agentCommandPolicy.commandz.typo = true;
            };
            expr = config.flake.homeConfigurations.tux.config.dotfiles.agentCommandPolicyCompiled;
          }
        )).expr;
      expectedFragments = [ "agentCommandPolicy.commandz" ];
    };
  };
in
if caseName == null then
  {
    inherit failureCases tests;
  }
else
  failureCases.${caseName}.expression
