{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./options.nix ] ++ modules;
    };

  failsToEvaluate =
    modules: !(builtins.tryEval (builtins.deepSeq (eval modules).config true)).success;

  evaluated = eval [
    {
      dotfiles.agentSkills.externalSkills.demo = {
        root = ./.;
        customization.frontmatter.additionalInheritedFields = [ "hidden" ];
        customization.body.replacements = [
          {
            from = "first";
            to = "first replacement";
          }
        ];
      };
    }
    {
      dotfiles.agentSkills.externalSkills.demo.customization = {
        frontmatter.additionalInheritedFields = [ "allowed-tools" ];
        frontmatter.set.description = "Demo skill.";
        body.replacements = [
          {
            from = "before";
            to = "after";
          }
        ];
        disableAutomaticInvocation = true;
      };
    }
  ];

  externalSkillsOption = evaluated.options.dotfiles.agentSkills.externalSkills;
  skillOptions = externalSkillsOption.type.getSubOptions [ ];
  customizationOptions = skillOptions.customization.type.getSubOptions [ ];
  frontmatterOptions = customizationOptions.frontmatter.type.getSubOptions [ ];
  bodyOptions = customizationOptions.body.type.getSubOptions [ ];
in
{
  testExternalSkillDefinitionsMergeAndNormalize = {
    expr = evaluated.config.dotfiles.agentSkills.externalSkills.demo;
    expected = {
      root = ./.;
      customization = {
        frontmatter = {
          set.description = "Demo skill.";
          additionalInheritedFields = [
            "hidden"
            "allowed-tools"
          ];
          remove = [ ];
        };
        body = {
          prepend = "";
          replacements = [
            {
              from = "first";
              to = "first replacement";
            }
            {
              from = "before";
              to = "after";
            }
          ];
        };
        disableAutomaticInvocation = true;
      };
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
        "set"
        "additionalInheritedFields"
        "remove"
      ];
      body = lib.all (name: builtins.hasAttr name bodyOptions) [
        "prepend"
        "replacements"
      ];
    };
    expected = {
      skill = true;
      customization = true;
      frontmatter = true;
      body = true;
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
          customization.frontmatter.additionalInheritedFields = [ "allowed tools" ];
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

  testExternalSkillOptionRejectsRequiredFieldRemoval = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.frontmatter.remove = [ "description" ];
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

  testExternalSkillOptionRejectsEmptyReplacementSource = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.body.replacements = [
            {
              from = "";
              to = "replacement";
            }
          ];
        };
      }
    ];
    expected = true;
  };

  testExternalSkillOptionRejectsUnknownReplacementField = {
    expr = failsToEvaluate [
      {
        dotfiles.agentSkills.externalSkills.demo = {
          root = ./.;
          customization.body.replacements = [
            {
              from = "before";
              to = "after";
              count = 1;
            }
          ];
        };
      }
    ];
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
}
