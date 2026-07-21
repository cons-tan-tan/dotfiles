# skill-policy.nix の純関数テスト。nix/tests/default.nix が
# *.test.nix を収集して lib.runTests を適用する。
{ lib }:
let
  fm =
    (import ./yaml-frontmatter.nix { inherit lib; }) // (import ./skill-policy.nix { inherit lib; });
  policy = import ./policy.nix { inherit lib; };

  withFm = "---\nname: demo\n---\nbody line\n";
  noFm = "body only\n---\nnot frontmatter\n";
  defaultInheritedFields = policy.defaultInheritedFrontmatterFields;
  prepare =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      root = ./.;
      inherit defaultInheritedFields customization;
    } original;
  prepareStrict =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      root = ./.;
      inherit defaultInheritedFields customization;
      requireExplicitFieldDecisions = true;
    } original;
  failsToEvaluate = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
in
{
  testApplyCustomization = {
    expr =
      fm.applyCustomization
        {
          name = "demo";
          root = ./.;
          customization = {
            frontmatter = {
              description = "New description.";
              set.allowed-tools = "Bash(example:*)";
            };
            body =
              {
                original,
                skillName,
                root,
              }:
              assert skillName == "demo";
              assert root == ./.;
              "NOTE\n" + builtins.replaceStrings [ "old" ] [ "new" ] original;
          };
        }
        ''
          ---
          name: demo
          description: Old description.
          ---
          old body
        '';
    expected = ''
      ---
      allowed-tools: "Bash(example:*)"
      name: demo
      description: "New description."
      ---
      NOTE
      new body
    '';
  };

  testPrepareSkillAppliesDeclarativePipeline = {
    expr =
      (prepare
        {
          frontmatter = {
            inheritFields = [
              "allowed-tools"
              "hidden"
            ];
            excludeFields = [ "license" ];
            description = "New description.";
          };
          body =
            { original, ... }:
            "NOTE\n" + builtins.replaceStrings [ "old" ] [ "new" ] original;
          disableAutomaticInvocation = true;
        }
        ''
          ---
          name: demo
          description: Old description.
          license: MIT
          allowed-tools: Bash(example:*)
          hidden: true
          hooks:
            PreToolUse: echo unsafe
          ---
          old body
        ''
      ).skillMd;
    expected = ''
      ---
      disable-model-invocation: true
      name: demo
      description: "New description."
      allowed-tools: Bash(example:*)
      hidden: true
      ---
      NOTE
      new body
    '';
  };

  testPrepareSkillDropsHiddenByDefault = {
    expr =
      (prepare { } ''
        ---
        name: demo
        description: Demo.
        hidden: true
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: Demo.
      ---
      body
    '';
  };

  testPrepareSkillInheritsHiddenWhenExplicitlyAllowed = {
    expr =
      (prepare { frontmatter.inheritFields = [ "hidden" ]; } ''
        ---
        name: demo
        description: Demo.
        hidden: true
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: Demo.
      hidden: true
      ---
      body
    '';
  };

  testPrepareSkillStrictModeAcceptsDefaultFields = {
    expr =
      (prepareStrict { } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: Demo.
      ---
      body
    '';
  };

  testPrepareSkillStrictModeRejectsUnclassifiedField = {
    expr = failsToEvaluate (
      prepareStrict { } ''
        ---
        name: demo
        description: Demo.
        allowed-tools: Bash(example:*)
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillStrictModeRejectsNewUpstreamField = {
    expr = failsToEvaluate (
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
        ''
    );
    expected = true;
  };

  testPrepareSkillStrictModeAcceptsExplicitExclusion = {
    expr =
      (prepareStrict { frontmatter.excludeFields = [ "allowed-tools" ]; } ''
        ---
        name: demo
        description: Demo.
        allowed-tools: Bash(example:*)
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: Demo.
      ---
      body
    '';
  };

  testPrepareSkillStrictModeAcceptsExplicitInheritance = {
    expr =
      (prepareStrict { frontmatter.inheritFields = [ "hidden" ]; } ''
        ---
        name: demo
        description: Demo.
        hidden: true
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: Demo.
      hidden: true
      ---
      body
    '';
  };

  testPrepareSkillRejectsConflictingFieldDecisions = {
    expr = failsToEvaluate (
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
        ''
    );
    expected = true;
  };

  testPrepareSkillRejectsStaleInheritedFieldDecision = {
    expr = failsToEvaluate (
      prepareStrict { frontmatter.inheritFields = [ "hidden" ]; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsMissingFrontmatter = {
    expr = failsToEvaluate (prepare { } "plain body\n");
    expected = true;
  };

  testPrepareSkillRejectsMissingRequiredField = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: demo
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillForcesValidationOnUnmodifiedResult = {
    expr = failsToEvaluate (
      (prepare { } ''
        ---
        name: demo
        ---
        body
      '').frontmatterWasFiltered
    );
    expected = true;
  };

  testPrepareSkillRejectsDuplicateRequiredField = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: demo
        name:
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsDistributionNameMismatch = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: other
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsNonStringDescription = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: demo
        description: []
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsNonStringDescriptionOverride = {
    expr = failsToEvaluate (
      prepare { frontmatter.description = true; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsDescriptionInGenericSet = {
    expr = failsToEvaluate (
      prepare { frontmatter.set.description = "Demo skill."; } ''
        ---
        name: demo
        description: Original description.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillFoldsMultilineDescriptionOverride = {
    expr =
      (prepare
        {
          frontmatter.description = ''
            Demo skill controls a CLI.
            Use it when automation is required.
          '';
        }
        ''
          ---
          name: demo
          description: Original description.
          ---
          body
        ''
      ).skillMd;
    expected = ''
      ---
      name: demo
      description: "Demo skill controls a CLI. Use it when automation is required."
      ---
      body
    '';
  };

  testPrepareSkillAccepts1024AsciiDescription = {
    expr = failsToEvaluate (
      prepare { frontmatter.description = lib.concatStrings (lib.replicate 1024 "a"); } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = false;
  };

  testPrepareSkillRejects1025AsciiDescription = {
    expr = failsToEvaluate (
      prepare { frontmatter.description = lib.concatStrings (lib.replicate 1025 "a"); } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillAccepts1024MultibyteDescription = {
    expr = failsToEvaluate (
      prepare { frontmatter.description = lib.concatStrings (lib.replicate 1024 "あ"); } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = false;
  };

  testPrepareSkillRejects1025MultibyteDescription = {
    expr = failsToEvaluate (
      prepare { frontmatter.description = lib.concatStrings (lib.replicate 1025 "あ"); } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterBlockDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: |\n  " + lib.concatStrings (lib.replicate 1023 "a") + "\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillRejects1025CharacterBlockDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: |\n  " + lib.concatStrings (lib.replicate 1024 "a") + "\n---\nbody\n"
      )
    );
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterStrippedBlockDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: |-\n  "
        + lib.concatStrings (lib.replicate 1024 "a")
        + "\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillAccepts1024CharacterFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  "
        + lib.concatStrings (lib.replicate 1022 "a")
        + "\n\n  b\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillRejects1025CharacterFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  "
        + lib.concatStrings (lib.replicate 1023 "a")
        + "\n\n  b\n---\nbody\n"
      )
    );
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterKeptFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >+\n  "
        + lib.concatStrings (lib.replicate 1022 "a")
        + "\n\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillAccepts1024CharacterMoreIndentedFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  x\n    "
        + lib.concatStrings (lib.replicate 1015 "a")
        + "\n\n    b\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillRejects1025CharacterMoreIndentedFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  x\n    "
        + lib.concatStrings (lib.replicate 1016 "a")
        + "\n\n    b\n---\nbody\n"
      )
    );
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterFoldBeforeMoreIndentedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  "
        + lib.concatStrings (lib.replicate 1019 "a")
        + "\n\n    b\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillRejects1025CharacterFoldBeforeMoreIndentedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  "
        + lib.concatStrings (lib.replicate 1020 "a")
        + "\n\n    b\n---\nbody\n"
      )
    );
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterTabContentFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  "
        + lib.concatStrings (lib.replicate 1020 "a")
        + "\n  \t\n  b\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillRejects1025CharacterTabContentFoldedDescription = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: >-\n  "
        + lib.concatStrings (lib.replicate 1021 "a")
        + "\n  \t\n  b\n---\nbody\n"
      )
    );
    expected = true;
  };

  testPrepareSkillAcceptsExplicitBlockIndent = {
    expr = failsToEvaluate (
      prepare { } (
        "---\nname: demo\ndescription: |2-\n  "
        + lib.concatStrings (lib.replicate 1024 "a")
        + "\n---\nbody\n"
      )
    );
    expected = false;
  };

  testPrepareSkillRejectsXmlInDescription = {
    expr = failsToEvaluate (
      prepare { frontmatter.description = "Use <example> when needed."; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsInvalidDistributionName = {
    expr = failsToEvaluate (
      fm.prepareSkill
        {
          name = "Invalid_Name";
          root = ./.;
          inherit defaultInheritedFields;
        }
        ''
          ---
          name: Invalid_Name
          description: Demo.
          ---
          body
        ''
    );
    expected = true;
  };

  testPrepareSkillRejectsEmptyBlockDescription = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: demo
        description: |
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsEmptyQuotedDescriptionWithComment = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: demo
        description: "" # empty
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillAcceptsNameWithInlineComment = {
    expr =
      (prepare { } ''
        ---
        name: demo # distribution name
        description: Demo.
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo # distribution name
      description: Demo.
      ---
      body
    '';
  };

  testPrepareSkillAcceptsApostropheInPlainDescription = {
    expr =
      (prepare { } ''
        ---
        name: demo
        description: It's useful # <ignored>
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: It's useful # <ignored>
      ---
      body
    '';
  };

  testPrepareSkillRejectsInvalidSingleQuotedDescription = {
    expr = failsToEvaluate (
      prepare { } ''
        ---
        name: demo
        description: 'foo'bar'
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillAcceptsEscapedSingleQuote = {
    expr = (prepare { } "---\nname: demo\ndescription: 'It''s useful'\n---\nbody\n").skillMd;
    expected = "---\nname: demo\ndescription: 'It''s useful'\n---\nbody\n";
  };

  testPrepareSkillTreatsIndentedHashAsBlockContent = {
    expr =
      (prepare { } ''
        ---
        name: demo
        description: |
          # literal description
        ---
        body
      '').skillMd;
    expected = ''
      ---
      name: demo
      description: |
        # literal description
      ---
      body
    '';
  };

  testPrepareSkillRejectsUnknownCustomizationKey = {
    expr = failsToEvaluate (
      prepare { disableAutomaticInvocaton = true; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsUnknownNestedKey = {
    expr = failsToEvaluate (
      prepare { frontmatter.additionalInheritedField = [ "allowed-tools" ]; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsLegacyBodyCustomization = {
    expr = failsToEvaluate (
      prepare
        {
          body.prepend = "NOTE\n";
        }
        ''
          ---
          name: demo
          description: Demo.
          ---
          body
        ''
    );
    expected = true;
  };

  testPrepareSkillRejectsNonStringBodyResult = {
    expr = failsToEvaluate (
      prepare { body = _: true; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsWrongType = {
    expr = failsToEvaluate (
      prepare { disableAutomaticInvocation = "true"; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsRequiredFieldExclusion = {
    expr = failsToEvaluate (
      prepare { frontmatter.excludeFields = [ "description" ]; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsUnknownExcludedField = {
    expr = failsToEvaluate (
      prepare { frontmatter.excludeFields = [ "allowed-tools" ]; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsLegacyFieldDecisionKeys = {
    expr = failsToEvaluate (
      prepare
        {
          frontmatter = {
            additionalInheritedFields = [ "hidden" ];
            remove = [ "allowed-tools" ];
          };
        }
        ''
          ---
          name: demo
          description: Demo.
          allowed-tools: Bash(example:*)
          hidden: true
          ---
          body
        ''
    );
    expected = true;
  };

  testValidateSkillDefinitionRejectsUnknownTopLevelKey = {
    expr = failsToEvaluate (
      fm.validateSkillDefinition "demo" {
        root = ./.;
        customisation.disableAutomaticInvocation = true;
      }
    );
    expected = true;
  };

  testValidateSkillDefinitionRejectsLegacyInvocationKey = {
    expr = failsToEvaluate (
      fm.validateSkillDefinition "demo" {
        root = ./.;
        disableAutomaticInvocation = true;
      }
    );
    expected = true;
  };

  testValidateSkillDefinitionIgnoresNormalizedEmptyCustomization = {
    expr =
      (fm.validateSkillDefinition "demo" {
        root = ./.;
        customization = {
          frontmatter = {
            description = null;
            set = { };
            inheritFields = [ ];
            excludeFields = [ ];
          };
          body = null;
          disableAutomaticInvocation = false;
        };
      }).hasCustomization;
    expected = false;
  };

  testValidateSkillDefinitionDetectsNormalizedCustomization = {
    expr =
      (fm.validateSkillDefinition "demo" {
        root = ./.;
        customization = {
          frontmatter = {
            description = null;
            set = { };
            inheritFields = [ "hidden" ];
            excludeFields = [ ];
          };
          body = null;
          disableAutomaticInvocation = false;
        };
      }).hasCustomization;
    expected = true;
  };

  testValidateSkillDefinitionAcceptsCallableBodyTransformer = {
    expr =
      (fm.validateSkillDefinition "demo" {
        root = ./.;
        customization.body = {
          __functor = _: { original, ... }: original;
        };
      }).hasCustomization;
    expected = true;
  };

  testMergeSkillDefinitionsKeepsDistinctSkills = {
    expr = builtins.attrNames (
      policy.mergeSkillDefinitions { external.root = ./.; } { local.root = ./.; }
    );
    expected = [
      "external"
      "local"
    ];
  };

  testMergeSkillDefinitionsRejectsCollision = {
    expr = failsToEvaluate (policy.mergeSkillDefinitions { demo.root = ./.; } { demo.root = ./.; });
    expected = true;
  };

}
