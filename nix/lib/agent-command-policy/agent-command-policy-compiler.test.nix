# 共有command policyのnative allowとguard policyへの非対称投影を確認する。
{ lib }:
let
  evalPolicy =
    module:
    let
      evaluated = lib.evalModules {
        modules = [
          ./options.nix
          { agentCommandPolicy = module; }
        ];
      };
      policy = evaluated.config.agentCommandPolicy;
    in
    import ./compiler.nix {
      inherit lib;
      inherit (policy) argv semantic shellfirm;
    };

  semanticLeaf = aliases: {
    optionSyntax = {
      valueTaking = [ "-C" ];
      optionalEquals = [ "--color" ];
    };
    deny = [
      {
        when.options.all = [ aliases ];
        reason = "Blocked by the fixture.";
        alternatives = [ "Use the safe fixture command." ];
      }
    ];
  };

  fixturePolicy = evalPolicy {
    argv = {
      lookup = {
        exact = true;
        group = {
          deep.path = true;
          first = true;
          second = true;
        };
      };
      remove = false;
    };
    semantic = {
      fd = semanticLeaf [
        "-x"
        "--exec"
      ];
      gh.pr.create = semanticLeaf [ "--fill" ];
    };
    shellfirm = {
      enabled = true;
      minimumSeverity = "High";
      categories.git = true;
      ruleNamespaces.git-strict = false;
      rules = {
        aws.delete_bucket = true;
        git.force_push = false;
      };
    };
  };

  actualPolicy = import ./default.nix { inherit lib; };
  markerNamePolicy = evalPolicy {
    semantic.demo = {
      deny.child = semanticLeaf [ "-x" ];
      optionSyntax.child = semanticLeaf [ "-y" ];
    };
  };

  failsToCompile = module: !(builtins.tryEval (builtins.deepSeq (evalPolicy module) true)).success;

  failsUncheckedCompile =
    policy:
    !(builtins.tryEval (builtins.deepSeq (import ./compiler.nix ({ inherit lib; } // policy)) true))
    .success;
in
{
  testOnlyTrueArgvLeavesProjectToNativeBackends = {
    expr = {
      claude = fixturePolicy.mkClaudePermissions { };
      codexPrefixes = map (rule: rule.argvPrefix) fixturePolicy.prefixRules;
      codexHasForbidden = lib.hasInfix ''decision = "forbidden"'' fixturePolicy.codexRulesContent;
    };
    expected = {
      claude = {
        allow = [
          "Bash(lookup exact *)"
          "Bash(lookup group deep path *)"
          "Bash(lookup group first *)"
          "Bash(lookup group second *)"
        ];
        deny = [ ];
      };
      codexPrefixes = [
        [
          "lookup"
          "exact"
        ]
        [
          "lookup"
          "group"
          "deep"
          "path"
        ]
        [
          "lookup"
          "group"
          "first"
        ]
        [
          "lookup"
          "group"
          "second"
        ]
      ];
      codexHasForbidden = false;
    };
  };

  testFalseArgvLeavesProjectOnlyToGuardExactDeny = {
    expr = fixturePolicy.guardPolicy.exact;
    expected = [
      {
        argvPrefix = [ "remove" ];
        decision = "deny";
        reason = "Forbidden by the shared agent command policy: remove.";
      }
    ];
  };

  testSemanticTreesFlattenToOneGenericShape = {
    expr = fixturePolicy.guardPolicy.semantic;
    expected = [
      {
        commandPrefix = [ "fd" ];
        optionSyntax = {
          valueTaking = [ "-C" ];
          optionalEquals = [ "--color" ];
        };
        deny = [
          {
            optionGroups = [
              [
                "-x"
                "--exec"
              ]
            ];
            reason = "Blocked by the fixture.";
            alternatives = [ "Use the safe fixture command." ];
          }
        ];
      }
      {
        commandPrefix = [
          "gh"
          "pr"
          "create"
        ];
        optionSyntax = {
          valueTaking = [ "-C" ];
          optionalEquals = [ "--color" ];
        };
        deny = [
          {
            optionGroups = [ [ "--fill" ] ];
            reason = "Blocked by the fixture.";
            alternatives = [ "Use the safe fixture command." ];
          }
        ];
      }
    ];
  };

  testSemanticMarkerNamesRemainUsableAsOrdinaryCommandTokens = {
    expr = map (rule: rule.commandPrefix) markerNamePolicy.guardPolicy.semantic;
    expected = [
      [
        "demo"
        "deny"
        "child"
      ]
      [
        "demo"
        "optionSyntax"
        "child"
      ]
    ];
  };

  testShellfirmSelectorPreservesMapsAndFlattensOnlyIndividualRules = {
    expr = fixturePolicy.guardPolicy.shellfirm;
    expected = {
      enabled = true;
      minimumSeverity = "High";
      categories.git = true;
      ruleNamespaces.git-strict = false;
      rules = {
        "aws:delete_bucket" = true;
        "git:force_push" = false;
      };
    };
  };

  testGeneratedPolicyKeepsUnknownBehaviorVersioned = {
    expr = {
      inherit (fixturePolicy.guardPolicy) schemaVersion unknown;
    };
    expected = {
      schemaVersion = 1;
      unknown = {
        parseError = "deny";
        dynamicExecutable = "deny";
        dynamicRelevantOption = "deny";
        maxDecodeDepth = 8;
      };
    };
  };

  testRepositoryPolicySelectsTheApprovedShellfirmSurface = {
    expr = {
      inherit (actualPolicy.guardPolicy.shellfirm) enabled minimumSeverity;
      enabledCategories = builtins.attrNames (
        lib.filterAttrs (_: decision: decision) actualPolicy.guardPolicy.shellfirm.categories
      );
      disabledNamespaces = builtins.attrNames (
        lib.filterAttrs (_: decision: !decision) actualPolicy.guardPolicy.shellfirm.ruleNamespaces
      );
      individualRules = actualPolicy.guardPolicy.shellfirm.rules;
      semanticCommands = map (rule: rule.commandPrefix) actualPolicy.guardPolicy.semantic;
    };
    expected = {
      enabled = true;
      minimumSeverity = "High";
      enabledCategories = [
        "aws"
        "docker"
        "fs"
        "gcp"
        "git"
        "github"
        "kubernetes"
        "network"
        "npm"
        "shell"
      ];
      disabledNamespaces = [
        "fs-strict"
        "git-strict"
        "kubernetes-strict"
      ];
      individualRules = { };
      semanticCommands = [
        [ "fd" ]
        [ "rm" ]
      ];
    };
  };

  testCompilerRejectsAnEmptyPolicy = {
    expr = failsToCompile { };
    expected = true;
  };

  testCompilerRejectsUnsafeArgvTokens = {
    expr = map failsToCompile [
      { argv."*" = true; }
      { argv."FOO=bar" = true; }
      { argv.safe."two words" = true; }
    ];
    expected = [
      true
      true
      true
    ];
  };

  testCompilerRejectsInvalidSemanticBoundaries = {
    expr = map failsUncheckedCompile [
      {
        argv.safe = true;
        semantic.demo = {
          optionSyntax = { };
          deny = [ ];
        };
      }
      {
        argv.safe = true;
        semantic.demo = semanticLeaf [
          "-x"
          "-x"
        ];
      }
      {
        argv.safe = true;
        semantic.demo = semanticLeaf [ "--" ];
      }
      {
        argv.safe = true;
        semantic.demo = semanticLeaf [ ];
      }
    ];
    expected = [
      true
      true
      true
      true
    ];
  };

  testCompilerRejectsInvalidShellfirmBoundaries = {
    expr = map failsUncheckedCompile [
      {
        argv.safe = true;
        shellfirm = {
          enabled = true;
          minimumSeverity = "Extreme";
          categories = { };
          ruleNamespaces = { };
          rules = { };
        };
      }
      {
        argv.safe = true;
        shellfirm = {
          enabled = true;
          minimumSeverity = "High";
          categories."bad:name" = true;
          ruleNamespaces = { };
          rules = { };
        };
      }
      {
        argv.safe = true;
        shellfirm = {
          enabled = true;
          minimumSeverity = "High";
          categories = { };
          ruleNamespaces = { };
          rules.git.force_push = "false";
        };
      }
    ];
    expected = [
      true
      true
      true
    ];
  };
}
