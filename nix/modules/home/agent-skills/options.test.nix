{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./options.nix ] ++ modules;
    };

  failsToEvaluate =
    modules: !(builtins.tryEval (builtins.deepSeq (eval modules).config true)).success;
  failsToEvaluateValue = value: !(builtins.tryEval (builtins.deepSeq value true)).success;

  evaluated = eval [
    {
      dotfiles.agentSkills.externalSkills.demo = {
        root = ./.;
        customization.frontmatter.inheritFields = [ "hidden" ];
        customization.body =
          { original, ... }:
          builtins.replaceStrings [ "first" ] [ "first replacement" ] original;
      };
    }
    {
      dotfiles.agentSkills.externalSkills.demo.customization = {
        frontmatter.inheritFields = [ "allowed-tools" ];
        frontmatter.description = "Demo skill.";
        disableAutomaticInvocation = true;
      };
    }
  ];

  externalSkillsOption = evaluated.options.dotfiles.agentSkills.externalSkills;
  skillOptions = externalSkillsOption.type.getSubOptions [ ];
  customizationOptions = skillOptions.customization.type.getSubOptions [ ];
  frontmatterOptions = customizationOptions.frontmatter.type.getSubOptions [ ];
  evaluatedSkill = evaluated.config.dotfiles.agentSkills.externalSkills.demo;
in
{
  testExternalSkillDefinitionsMergeAndNormalize = {
    expr = {
      inherit (evaluatedSkill) root;
      inherit (evaluatedSkill.customization) frontmatter disableAutomaticInvocation;
      body = evaluatedSkill.customization.body {
        original = "first body";
        skillName = "demo";
        root = ./.;
      };
    };
    expected = {
      root = ./.;
      frontmatter = {
        description = "Demo skill.";
        set = { };
        inheritFields = [
          "hidden"
          "allowed-tools"
        ];
        excludeFields = [ ];
      };
      body = "first replacement body";
      disableAutomaticInvocation = true;
    };
  };

  testExternalSkillOptionExposesNixdSubOptions = {
    expr = {
      skill = lib.all (name: builtins.hasAttr name skillOptions) [
        "root"
        "customization"
      ];
      customization = lib.all (name: builtins.hasAttr name customizationOptions) [
        "frontmatter"
        "body"
        "disableAutomaticInvocation"
      ];
      frontmatter = lib.all (name: builtins.hasAttr name frontmatterOptions) [
        "description"
        "set"
        "inheritFields"
        "excludeFields"
      ];
    };
    expected = {
      skill = true;
      customization = true;
      frontmatter = true;
    };
  };

  testExternalSkillOptionRejectsUnknownSkillField = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customisation = { };
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsInvalidSkillName = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills."Invalid_Name".root = ./.;
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRequiresRoot = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo.customization.disableAutomaticInvocation = true;
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsWrongInvocationType = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.disableAutomaticInvocation = "true";
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsInvalidFrontmatterField = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter.inheritFields = [ "allowed tools" ];
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsInvalidSetField = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter.set."allowed tools" = "unsafe";
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsDescriptionInSet = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter.set.description = "Demo skill.";
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsRequiredFieldExclusion = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter.excludeFields = [ "description" ];
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsNonJsonSetValue = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter.set.hooks = _: "not JSON";
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsLegacyBodyCustomization = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.body.prepend = "NOTE\n";
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsDuplicateBodyTransformers = {
    expr =
      let
        conflicting = eval [
          {
            dotfiles.agentSkills.externalSkills.demo = {
              root = ./.;
              customization.body = _: "same";
            };
          }
          {
            dotfiles.agentSkills.externalSkills.demo.customization.body = _: "same";
          }
        ];
      in
      failsToEvaluateValue (
        conflicting.config.dotfiles.agentSkills.externalSkills.demo.customization.body {
          original = "body";
          skillName = "demo";
          root = ./.;
        }
      );
    expected = true;
  };

  testExternalSkillOptionRejectsUnknownNestedField = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter."inherit" = [ "allowed-tools" ];
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsLegacyFrontmatterFields = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter = {
            additionalInheritedFields = [ "hidden" ];
            remove = [ "allowed-tools" ];
          };
        };
      }
    ];
    expected = true;
  };
}
