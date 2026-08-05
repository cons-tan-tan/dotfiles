{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  optionsModule = repoRoot + "/modules/features/agents/skills/_interface/options.nix";
  eval =
    modules:
    lib.evalModules {
      modules = [ optionsModule ] ++ modules;
    };
  evalConfig = modules: builtins.deepSeq (eval modules).config true;
  cases = {
    rejectsUnknownSkillField = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customisation = { };
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customisation";
    };

    rejectsInvalidSkillName = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills."Invalid_Name".root = ./.;
        }
      ];
      expectedFragment = "external skill names must use 1-64 lowercase letters, digits, and hyphens";
    };

    rejectsMissingRoot = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo.customization.disableAutomaticInvocation = true;
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.root";
    };

    rejectsWrongInvocationType = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.disableAutomaticInvocation = "true";
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.disableAutomaticInvocation";
    };

    rejectsInvalidInheritedFrontmatterField = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.inheritFields = [ "allowed tools" ];
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.frontmatter.inheritFields";
    };

    rejectsInvalidSetFieldName = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.set."allowed tools" = "unsafe";
          };
        }
      ];
      expectedFragment = "frontmatter.set contains an invalid field name";
    };

    rejectsDescriptionInSet = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.set.description = "Demo skill.";
          };
        }
      ];
      expectedFragment = "frontmatter.set.description is unsupported";
    };

    rejectsRequiredFieldExclusion = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.excludeFields = [ "description" ];
          };
        }
      ];
      expectedFragment = "frontmatter.excludeFields cannot exclude required";
    };

    rejectsNonJsonSetValue = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.set.hooks = _: "not JSON";
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.frontmatter.set.hooks";
    };

    rejectsLegacyBodyCustomization = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.body.prepend = "NOTE\n";
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.body";
    };

    rejectsDuplicateBodyTransformers = {
      expression =
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
        conflicting.config.dotfiles.agentSkills.externalSkills.demo.customization.body {
          original = "body";
          skillName = "demo";
          root = ./.;
        };
      expectedFragment = "Only one body transformer";
    };

    rejectsUnknownNestedFrontmatterField = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter."inherit" = [ "allowed-tools" ];
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.frontmatter.inherit";
    };

    rejectsLegacyAdditionalInheritedFields = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.additionalInheritedFields = [ "hidden" ];
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.frontmatter.additionalInheritedFields";
    };

    rejectsLegacyRemoveFields = {
      expression = evalConfig [
        {
          dotfiles.agentSkills.externalSkills.demo = {
            root = ./.;
            customization.frontmatter.remove = [ "allowed-tools" ];
          };
        }
      ];
      expectedFragment = "dotfiles.agentSkills.externalSkills.demo.customization.frontmatter.remove";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
