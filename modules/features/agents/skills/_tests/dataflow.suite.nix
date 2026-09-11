{
  caseName ? null,
  inputs,
  lib,
  repoRoot ? ../../../../..,
}:
let
  meta = {
    checkName = "agent-skills-dataflow-tests";
    execution = "build";
    hestiaGroup = "eval-tests";
  };
  skillsRoot = repoRoot + "/modules/features/agents/skills";

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
    testSkillQuirkMergesProducersWithoutLeakingAcrossHomes = evalTest (
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
        den.aspects.skills-local.agent-skills =
          { pkgs, ... }:
          [
            {
              name = "local";
              definition.root = "${pkgs.writeTextDir "SKILL.md" ''
                ---
                name: local
                description: Generated skill.
                ---
                body
              ''}";
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
            localSourceRendered =
              toString tuxHm.home.file.".agents/skills/local".source
              != toString tuxHm.dotfiles.agentSkills.externalSkills.local.root;
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
            localSourceRendered = true;
          };
          pingu = {
            names = [ ];
            leaked = false;
          };
        };
      }
    );
  };

  failureCases = { };
in
if caseName == null then
  {
    inherit failureCases meta tests;
  }
else
  failureCases.${caseName}.expression
