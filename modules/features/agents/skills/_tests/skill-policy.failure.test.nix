{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  sourceRoot = repoRoot + "/modules/features/agents/skills/_lib";
  fm =
    (import (sourceRoot + "/yaml-frontmatter.nix") { inherit lib; })
    // (import (sourceRoot + "/skill-policy.nix") { inherit lib; });
  policy = import (repoRoot + "/modules/features/agents/skills/_data/policy.nix") { inherit lib; };

  defaultInheritedFields = policy.defaultInheritedFrontmatterFields;
  prepare =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      root = sourceRoot;
      inherit defaultInheritedFields customization;
    } original;
  prepareStrict =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      root = sourceRoot;
      inherit defaultInheritedFields customization;
      requireExplicitFieldDecisions = true;
    } original;
  validSkill = ''
    ---
    name: demo
    description: Demo.
    ---
    body
  '';

  cases = {
    unclassifiedUpstreamField = {
      expression = prepareStrict { } ''
        ---
        name: demo
        description: Demo.
        allowed-tools: Bash(example:*)
        ---
        body
      '';
      expectedFragment = "skill demo customization.frontmatter has unclassified upstream fields: allowed-tools";
    };

    newlyUnclassifiedUpstreamField = {
      expression =
        prepareStrict
          {
            frontmatter = {
              inheritFields = [ "hidden" ];
              excludeFields = [ "allowed-tools" ];
            };
          }
          ''
            ---
            name: demo
            description: Demo.
            allowed-tools: Bash(example:*)
            hidden: true
            hooks:
              PreToolUse: echo unsafe
            ---
            body
          '';
      expectedFragment = "skill demo customization.frontmatter has unclassified upstream fields: hooks";
    };

    conflictingFieldDecisions = {
      expression =
        prepareStrict
          {
            frontmatter = {
              inheritFields = [ "hidden" ];
              excludeFields = [ "hidden" ];
            };
          }
          ''
            ---
            name: demo
            description: Demo.
            hidden: true
            ---
            body
          '';
      expectedFragment = "skill demo customization.frontmatter fields cannot be both inherited and excluded: hidden";
    };

    staleInheritedFieldDecision = {
      expression = prepareStrict { frontmatter.inheritFields = [ "hidden" ]; } validSkill;
      expectedFragment = "skill demo customization.frontmatter decisions reference fields missing from upstream: hidden";
    };

    missingUpstreamFrontmatter = {
      expression = prepare { } "plain body\n";
      expectedFragment = "skill demo: upstream SKILL.md requires YAML frontmatter";
    };

    missingDescriptionField = {
      expression = prepare { } ''
        ---
        name: demo
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter must contain exactly one description field";
    };

    unmodifiedResultStillValidated = {
      expression =
        (prepare { } ''
          ---
          name: demo
          ---
          body
        '').frontmatterWasFiltered;
      expectedFragment = "skill demo: frontmatter must contain exactly one description field";
    };

    duplicateNameField = {
      expression = prepare { } ''
        ---
        name: demo
        name:
        description: Demo.
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter must contain exactly one name field";
    };

    distributionNameMismatch = {
      expression = prepare { } ''
        ---
        name: other
        description: Demo.
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter.name must be a string matching its distribution name";
    };

    nonStringSourceDescription = {
      expression = prepare { } ''
        ---
        name: demo
        description: []
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter.description must be a non-empty string";
    };

    nonStringDescriptionOverride = {
      expression = prepare { frontmatter.description = true; } validSkill;
      expectedFragment = "skill demo customization.frontmatter.description must be a string";
    };

    descriptionInGenericSet = {
      expression = prepare { frontmatter.set.description = "Demo skill."; } validSkill;
      expectedFragment = "skill demo customization.frontmatter.set.description is unsupported";
    };

    asciiDescriptionOverLimit = {
      expression = prepare {
        frontmatter.description = lib.concatStrings (lib.replicate 1025 "a");
      } validSkill;
      expectedFragment = "skill demo: frontmatter.description must not exceed 1024 characters";
    };

    multibyteDescriptionOverLimit = {
      expression = prepare {
        frontmatter.description = lib.concatStrings (lib.replicate 1025 "あ");
      } validSkill;
      expectedFragment = "skill demo: frontmatter.description must not exceed 1024 characters";
    };

    literalBlockDescriptionOverLimit = {
      expression = prepare { } (
        "---\nname: demo\ndescription: |\n  " + lib.concatStrings (lib.replicate 1024 "a") + "\n---\nbody\n"
      );
      expectedFragment = "skill demo: frontmatter.description must not exceed 1024 characters";
    };

    xmlTagInDescription = {
      expression = prepare { frontmatter.description = "Use <example> when needed."; } validSkill;
      expectedFragment = "skill demo: frontmatter.description must not contain XML tags";
    };

    invalidDistributionName = {
      expression =
        fm.prepareSkill
          {
            name = "Invalid_Name";
            root = sourceRoot;
            inherit defaultInheritedFields;
          }
          ''
            ---
            name: Invalid_Name
            description: Demo.
            ---
            body
          '';
      expectedFragment = "skill distribution name must use 1-64 lowercase letters, digits, and hyphens: Invalid_Name";
    };

    emptyLiteralBlockDescription = {
      expression = prepare { } ''
        ---
        name: demo
        description: |
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter.description must be a non-empty string";
    };

    emptyQuotedDescription = {
      expression = prepare { } ''
        ---
        name: demo
        description: "" # empty
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter.description must be a non-empty string";
    };

    invalidSingleQuotedDescription = {
      expression = prepare { } ''
        ---
        name: demo
        description: 'foo'bar'
        ---
        body
      '';
      expectedFragment = "skill demo: frontmatter.description must be a non-empty string";
    };

    unknownCustomizationKey = {
      expression = prepare { disableAutomaticInvocaton = true; } validSkill;
      expectedFragment = "skill demo customization: unknown attributes: disableAutomaticInvocaton";
    };

    unknownFrontmatterCustomizationKey = {
      expression = prepare {
        frontmatter.additionalInheritedField = [ "allowed-tools" ];
      } validSkill;
      expectedFragment = "skill demo customization.frontmatter: unknown attributes: additionalInheritedField";
    };

    legacyBodyCustomization = {
      expression = prepare { body.prepend = "NOTE\n"; } validSkill;
      expectedFragment = "skill demo customization.body must be a function";
    };

    nonStringBodyResult = {
      expression = prepare { body = _: true; } validSkill;
      expectedFragment = "skill demo customization.body must return a string";
    };

    nonBooleanInvocationPolicy = {
      expression = prepare { disableAutomaticInvocation = "true"; } validSkill;
      expectedFragment = "skill demo customization.disableAutomaticInvocation must be a boolean";
    };

    requiredFieldExclusion = {
      expression = prepare { frontmatter.excludeFields = [ "description" ]; } validSkill;
      expectedFragment = "skill demo customization.frontmatter.excludeFields cannot exclude required name or description fields";
    };

    staleExcludedFieldDecision = {
      expression = prepare { frontmatter.excludeFields = [ "allowed-tools" ]; } validSkill;
      expectedFragment = "skill demo customization.frontmatter decisions reference fields missing from upstream: allowed-tools";
    };

    legacyAdditionalInheritedFieldsKey = {
      expression = prepare {
        frontmatter.additionalInheritedFields = [ "hidden" ];
      } validSkill;
      expectedFragment = "skill demo customization.frontmatter: unknown attributes: additionalInheritedFields";
    };

    legacyRemoveKey = {
      expression = prepare {
        frontmatter.remove = [ "allowed-tools" ];
      } validSkill;
      expectedFragment = "skill demo customization.frontmatter: unknown attributes: remove";
    };

    unknownSkillDefinitionKey = {
      expression = fm.validateSkillDefinition "demo" {
        root = sourceRoot;
        customisation.disableAutomaticInvocation = true;
      };
      expectedFragment = "skill demo definition: unknown attributes: customisation";
    };

    legacyInvocationDefinitionKey = {
      expression = fm.validateSkillDefinition "demo" {
        root = sourceRoot;
        disableAutomaticInvocation = true;
      };
      expectedFragment = "skill demo definition: unknown attributes: disableAutomaticInvocation";
    };

  };
in
if caseName == null then cases else cases.${caseName}.expression
