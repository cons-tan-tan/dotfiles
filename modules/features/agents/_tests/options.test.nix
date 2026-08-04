{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ../_lib/skills/options.nix ] ++ modules;
    };

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

}
