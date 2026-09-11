{ lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (import ../_lib/yaml-frontmatter.nix { inherit lib; }) isFrontmatterFieldName;
  inherit (import ../_lib/skill-policy.nix { inherit lib; }) isSkillName;

  frontmatterFieldType = types.strMatching "^[A-Za-z0-9_-]+$";
  validateSetFieldNames =
    values:
    assert lib.assertMsg (lib.all isFrontmatterFieldName (
      builtins.attrNames values
    )) "frontmatter.set contains an invalid field name";
    assert lib.assertMsg (
      !values ? description
    ) "frontmatter.set.description is unsupported; use frontmatter.description";
    values;
  validateExcludedFields =
    fields:
    assert lib.assertMsg (lib.all (
      field:
      !builtins.elem field [
        "name"
        "description"
      ]
    ) fields) "frontmatter.excludeFields cannot exclude required name or description fields";
    fields;
  validateSkillNames =
    skills:
    assert lib.assertMsg (lib.all isSkillName (
      builtins.attrNames skills
    )) "external skill names must use 1-64 lowercase letters, digits, and hyphens";
    skills;
  bodyType = types.submodule {
    options = {
      program = mkOption {
        type = types.path;
        description = "Nix program imported during the skill build; it must return a body transformer.";
      };
      arguments = mkOption {
        default = { };
        type = types.attrsOf types.raw;
        apply =
          arguments:
          builtins.addErrorContext "while serializing customization.body.arguments to JSON" (
            builtins.seq (builtins.toJSON arguments) arguments
          );
        description = "Explicit JSON-serializable arguments passed to the build-time body transformer.";
      };
    };
  };

  customizationType = types.submodule {
    options = {
      frontmatter = mkOption {
        default = { };
        type = types.submodule {
          options = {
            description = mkOption {
              default = null;
              type = types.nullOr types.str;
              description = "Replacement skill description; multiline text is folded into one line.";
            };
            set = mkOption {
              default = { };
              type = types.attrsOf types.json;
              apply = validateSetFieldNames;
              description = "Frontmatter fields to set using JSON-encoded Nix values.";
            };
            inheritFields = mkOption {
              default = [ ];
              type = types.listOf frontmatterFieldType;
              description = "Upstream frontmatter fields explicitly inherited for this skill.";
            };
            excludeFields = mkOption {
              default = [ ];
              type = types.listOf frontmatterFieldType;
              apply = validateExcludedFields;
              description = "Upstream frontmatter fields explicitly excluded for this skill.";
            };
          };
        };
        description = "Declarative frontmatter transformations.";
      };

      body = mkOption {
        default = null;
        type = types.nullOr (
          types.unique {
            message = "Only one body transformer may be defined for each skill.";
          } (types.addCheck bodyType builtins.isAttrs)
        );
        description = "Build-time Nix body transformer and its explicit arguments.";
        example = lib.literalExpression ''
          {
            program = ./agent-skills/example;
            arguments.notice = "Managed locally";
          }
        '';
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
        type = types.path;
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
