# frontmatter.nix の純関数テスト。lib.runTests は失敗ケースのリストを返す
# (空リスト = 全 pass)。flake.nix の checks が eval 時に空であることを
# assert するため、退行は nix flake check --no-build の段階で検知される。
{ lib }:
let
  fm = import ./frontmatter.nix { inherit lib; };

  withFm = "---\nname: demo\n---\nbody line\n";
  noFm = "body only\n---\nnot frontmatter\n";
  defaultInheritedFields = [
    "name"
    "description"
    "license"
    "compatibility"
    "metadata"
    "hidden"
  ];
  prepare =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      inherit defaultInheritedFields customization;
    } original;
  failsToEvaluate = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
in
lib.runTests {
  testSplitWithFrontmatter = {
    expr = fm.splitFrontmatter withFm;
    expected = {
      frontmatter = "---\nname: demo\n---\n";
      body = "body line\n";
    };
  };

  # 先頭が "---\n" でなければ全体を本文として扱う
  testSplitWithoutFrontmatter = {
    expr = fm.splitFrontmatter noFm;
    expected = {
      frontmatter = "";
      body = noFm;
    };
  };

  # 本文中の "\n---\n" (Markdown の水平線) が分割で失われないこと
  testSplitBodyKeepsHr = {
    expr = (fm.splitFrontmatter "---\na: 1\n---\npart1\n---\npart2\n").body;
    expected = "part1\n---\npart2\n";
  };

  testSplitNormalizesBomAndCrLf = {
    expr = fm.splitFrontmatter "${fm.utf8Bom}---\r\nname: demo\r\n---\r\nbody\r\n";
    expected = {
      frontmatter = "---\nname: demo\n---\n";
      body = "body\n";
    };
  };

  testSplitClosingDelimiterAtEof = {
    expr = fm.splitFrontmatter "---\nname: demo\n---";
    expected = {
      frontmatter = "---\nname: demo\n---\n";
      body = "";
    };
  };

  testSplitRejectsUnterminatedFrontmatter = {
    expr = failsToEvaluate (fm.splitFrontmatter "---\nname: demo\nbody\n");
    expected = true;
  };

  testFoldYamlBlockLines = {
    expr = fm.foldYamlBlockLines [
      "first"
      "second"
      ""
      "third"
    ];
    expected = "first second\nthird";
  };

  testFoldYamlBlockLinesPreservesMoreIndentedBreaks = {
    expr = fm.foldYamlBlockLines [
      "first"
      "  indented"
      ""
      "last"
    ];
    expected = "first\n  indented\n\nlast";
  };

  testFoldYamlBlockLinesPreservesBreakBeforeMoreIndentedLine = {
    expr = fm.foldYamlBlockLines [
      "first"
      ""
      "  indented"
    ];
    expected = "first\n\n  indented";
  };

  testFoldYamlBlockLinesTreatsTabAsContent = {
    expr = fm.foldYamlBlockLines [
      "first"
      "\t"
      "last"
    ];
    expected = "first\n\t\nlast";
  };

  testSetFrontmatterFieldWithFrontmatter = {
    expr = fm.setFrontmatterField "disable-model-invocation" "true" withFm;
    expected = "---\ndisable-model-invocation: true\nname: demo\n---\nbody line\n";
  };

  testSetFrontmatterFieldWithoutFrontmatter = {
    expr = fm.setFrontmatterField "disable-model-invocation" "true" noFm;
    expected = "---\ndisable-model-invocation: true\n---\n${noFm}";
  };

  testSetFrontmatterFieldReplacesExisting = {
    expr = fm.setFrontmatterField "disable-model-invocation" "true" ''
      ---
      name: demo
      disable-model-invocation: false
      ---
      body
    '';
    expected = ''
      ---
      name: demo
      disable-model-invocation: true
      ---
      body
    '';
  };

  testSetFrontmatterFieldReplacesBlockValue = {
    expr = fm.setFrontmatterField "description" "New description." ''
      ---
      name: demo
      description: |
        Old description.
        More old text.
      license: MIT
      ---
      body
    '';
    expected = ''
      ---
      name: demo
      description: New description.
      license: MIT
      ---
      body
    '';
  };

  testFilterFrontmatterFields = {
    expr =
      fm.filterFrontmatterFields
        [
          "name"
          "description"
          "license"
          "compatibility"
          "metadata"
          "hidden"
        ]
        ''
          ---
          name: demo
          description: |
            Multi-line description.
          license: MIT
          compatibility: Requires git and network access
          metadata:
            author: Example
          allowed-tools: Bash(example:*)
          hooks:
            PreToolUse: echo unsafe
          hidden: true
          ---
          body
        '';
    expected = ''
      ---
      name: demo
      description: |
        Multi-line description.
      license: MIT
      compatibility: Requires git and network access
      metadata:
        author: Example
      hidden: true
      ---
      body
    '';
  };

  testFilterFrontmatterFieldsAllowsExplicitField = {
    expr =
      fm.filterFrontmatterFields
        [
          "name"
          "description"
          "allowed-tools"
        ]
        ''
          ---
          name: demo
          description: Demo.
          allowed-tools: Bash(example:*)
          hidden: true
          ---
          body
        '';
    expected = ''
      ---
      name: demo
      description: Demo.
      allowed-tools: Bash(example:*)
      ---
      body
    '';
  };

  # YAML merge key など、許可fieldの継続行ではない構文は保持しない。
  testFilterFrontmatterFieldsDropsUnknownTopLevelSyntax = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] ''
      ---
      name: demo
      description: Demo.
      <<: *defaults
        allowed-tools: Bash(example:*)
      ---
      body
    '';
    expected = ''
      ---
      name: demo
      description: Demo.
      ---
      body
    '';
  };

  testFilterFrontmatterFieldsWithoutFrontmatter = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] noFm;
    expected = noFm;
  };

  testFilterFrontmatterFieldsBlocksAllowedToolsWithCrLf = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] (
      "---\r\nname: demo\r\ndescription: Demo.\r\nallowed-tools: Bash(example:*)\r\n---\r\nbody\r\n"
    );
    expected = "---\nname: demo\ndescription: Demo.\n---\nbody\n";
  };

  testFilterFrontmatterFieldsBlocksAllowedToolsWithBom = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] (
      "${fm.utf8Bom}---\nname: demo\ndescription: Demo.\nallowed-tools: Bash(example:*)\n---\nbody\n"
    );
    expected = "---\nname: demo\ndescription: Demo.\n---\nbody\n";
  };

  testApplyCustomization = {
    expr =
      fm.applyCustomization
        {
          frontmatter.set = {
            allowed-tools = "Bash(example:*)";
            description = "New description.";
          };
          body = {
            prepend = "NOTE\n";
            replacements = [
              {
                from = "old";
                to = "new";
              }
            ];
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
            additionalInheritedFields = [ "allowed-tools" ];
            remove = [ "license" ];
            set.description = "New description.";
          };
          body = {
            prepend = "NOTE\n";
            replacements = [
              {
                from = "old";
                to = "new";
              }
            ];
          };
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
      prepare { frontmatter.set.description = true; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testUtf8CodePointLength = {
    expr = fm.utf8CodePointLength "aあ🙂";
    expected = 3;
  };

  testPrepareSkillAccepts1024AsciiDescription = {
    expr = failsToEvaluate (
      prepare { frontmatter.set.description = lib.concatStrings (lib.replicate 1024 "a"); } ''
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
      prepare { frontmatter.set.description = lib.concatStrings (lib.replicate 1025 "a"); } ''
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
      prepare { frontmatter.set.description = lib.concatStrings (lib.replicate 1024 "あ"); } ''
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
      prepare { frontmatter.set.description = lib.concatStrings (lib.replicate 1025 "あ"); } ''
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
      prepare { frontmatter.set.description = "Use <example> when needed."; } ''
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

  testPrepareSkillRejectsUnknownReplacementKey = {
    expr = failsToEvaluate (
      prepare
        {
          body.replacements = [
            {
              from = "old";
              into = "new";
              to = "new";
            }
          ];
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

  testPrepareSkillRejectsRequiredFieldRemoval = {
    expr = failsToEvaluate (
      prepare { frontmatter.remove = [ "description" ]; } ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    );
    expected = true;
  };

  testPrepareSkillRejectsUnknownRemovedField = {
    expr = failsToEvaluate (
      prepare { frontmatter.remove = [ "allowed-tools" ]; } ''
        ---
        name: demo
        description: Demo.
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

  testCodexPolicyCreatedWhenMissingFile = {
    expr = fm.disableCodexImplicitInvocation "";
    expected = ''
      policy:
        allow_implicit_invocation: false
    '';
  };

  testCodexPolicyAppendedWithoutDroppingInterface = {
    expr = fm.disableCodexImplicitInvocation ''
      interface:
        display_name: 'Difit'
        default_prompt: 'Use $difit.'
    '';
    expected = ''
      interface:
        display_name: 'Difit'
        default_prompt: 'Use $difit.'

      policy:
        allow_implicit_invocation: false
    '';
  };

  testCodexPolicyInsertedIntoExistingPolicy = {
    expr = fm.disableCodexImplicitInvocation ''
      interface:
        display_name: 'Demo'
      policy:
        other: true
    '';
    expected = ''
      interface:
        display_name: 'Demo'
      policy:
        allow_implicit_invocation: false
        other: true
    '';
  };

  testCodexPolicyReplacesExistingValue = {
    expr = fm.disableCodexImplicitInvocation ''
      policy:
        allow_implicit_invocation: true
        other: true
    '';
    expected = ''
      policy:
        allow_implicit_invocation: false
        other: true
    '';
  };

}
