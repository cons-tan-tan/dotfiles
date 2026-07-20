{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ./frontmatter.nix { inherit lib; }) isFrontmatterFieldName isSkillName;

  frontmatterFieldType = types.strMatching "^[A-Za-z0-9_-]+$";
  validateSetFieldNames =
    values:
    assert lib.assertMsg (lib.all isFrontmatterFieldName (
      builtins.attrNames values
    )) "frontmatter.set contains an invalid field name";
    values;
  validateRemovableFields =
    fields:
    assert lib.assertMsg (lib.all (
      field:
      !builtins.elem field [
        "name"
        "description"
      ]
    ) fields) "frontmatter.remove cannot remove required name or description fields";
    fields;
  validateSkillNames =
    skills:
    assert lib.assertMsg (lib.all isSkillName (
      builtins.attrNames skills
    )) "external skill names must use 1-64 lowercase letters, digits, and hyphens";
    skills;

  replacementType = types.submodule {
    options = {
      from = mkOption {
        type = types.nonEmptyStr;
        description = "Exact body text to replace.";
      };
      to = mkOption {
        type = types.str;
        description = "Replacement body text.";
      };
    };
  };

  customizationType = types.submodule {
    options = {
      frontmatter = mkOption {
        default = { };
        type = types.submodule {
          options = {
            set = mkOption {
              default = { };
              type = types.attrsOf types.json;
              apply = validateSetFieldNames;
              description = "Frontmatter fields to set using JSON-encoded Nix values.";
            };
            additionalInheritedFields = mkOption {
              default = [ ];
              type = types.listOf frontmatterFieldType;
              description = "Upstream frontmatter fields explicitly allowed for this skill.";
            };
            remove = mkOption {
              default = [ ];
              type = types.listOf frontmatterFieldType;
              apply = validateRemovableFields;
              description = "Otherwise inherited frontmatter fields to remove.";
            };
          };
        };
        description = "Declarative frontmatter transformations.";
      };

      body = mkOption {
        default = { };
        type = types.submodule {
          options = {
            prepend = mkOption {
              default = "";
              type = types.str;
              description = "Text prepended to the skill body.";
            };
            replacements = mkOption {
              default = [ ];
              type = types.listOf replacementType;
              description = "Ordered exact-text replacements applied to the skill body.";
            };
          };
        };
        description = "Declarative body transformations.";
      };

      disableAutomaticInvocation = mkOption {
        default = false;
        type = types.bool;
        description = "Disable implicit or automatic invocation for supported agents.";
      };
    };
  };

  skillType = types.submodule {
    options = {
      root = mkOption {
        type = types.either types.path types.str;
        description = "Directory containing the skill's SKILL.md.";
      };
      customization = mkOption {
        default = { };
        type = customizationType;
        description = "Local transformations and invocation policy for the skill.";
      };
    };
  };

in
{
  options.dotfiles.agentSkills.externalSkills = mkOption {
    default = { };
    type = types.attrsOf skillType;
    apply = validateSkillNames;
    description = "External skills deployed to the configured agent skill directories.";
  };
}
