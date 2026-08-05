# skill-policy.nix の純関数の契約テスト。
{ lib }:
let
  fm =
    (import ../_lib/yaml-frontmatter.nix { inherit lib; })
    // (import ../_lib/skill-policy.nix { inherit lib; });
  policy = import ../_lib/policy.nix { inherit lib; };

  defaultInheritedFields = policy.defaultInheritedFrontmatterFields;
  prepare =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      root = ../_lib;
      inherit defaultInheritedFields customization;
    } original;
  prepareStrict =
    customization: original:
    fm.prepareSkill {
      name = "demo";
      root = ../_lib;
      inherit defaultInheritedFields customization;
      requireExplicitFieldDecisions = true;
    } original;
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
    expr = builtins.deepSeq (prepare
      { frontmatter.description = lib.concatStrings (lib.replicate 1024 "a"); }
      ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    ) true;
    expected = true;
  };

  testPrepareSkillAccepts1024MultibyteDescription = {
    expr = builtins.deepSeq (prepare
      { frontmatter.description = lib.concatStrings (lib.replicate 1024 "あ"); }
      ''
        ---
        name: demo
        description: Demo.
        ---
        body
      ''
    ) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterBlockDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: |\n  " + lib.concatStrings (lib.replicate 1023 "a") + "\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterStrippedBlockDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: |-\n  "
      + lib.concatStrings (lib.replicate 1024 "a")
      + "\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterFoldedDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: >-\n  "
      + lib.concatStrings (lib.replicate 1022 "a")
      + "\n\n  b\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterKeptFoldedDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: >+\n  "
      + lib.concatStrings (lib.replicate 1022 "a")
      + "\n\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterMoreIndentedFoldedDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: >-\n  x\n    "
      + lib.concatStrings (lib.replicate 1015 "a")
      + "\n\n    b\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterFoldBeforeMoreIndentedDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: >-\n  "
      + lib.concatStrings (lib.replicate 1019 "a")
      + "\n\n    b\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAccepts1024CharacterTabContentFoldedDescription = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: >-\n  "
      + lib.concatStrings (lib.replicate 1020 "a")
      + "\n  \t\n  b\n---\nbody\n"
    )) true;
    expected = true;
  };

  testPrepareSkillAcceptsExplicitBlockIndent = {
    expr = builtins.deepSeq (prepare { } (
      "---\nname: demo\ndescription: |2-\n  "
      + lib.concatStrings (lib.replicate 1024 "a")
      + "\n---\nbody\n"
    )) true;
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

}
