# 単一command treeからnative allowと共通guardが一貫して生成されることを確認する。
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
      inherit (policy)
        commands
        shell
        shellfirm
        ;
    };

  semanticCommand = aliases: {
    decision = true;
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
    commands = {
      lookup = {
        exact = true;
        group.deep.path = true;
      };
      remove = false;
      fd =
        (semanticCommand [
          "-x"
          "--exec"
        ])
        // {
          guidance = "Use the fixture.";
        };
      gh.pr.create = semanticCommand [ "--fill" ];
    };
    shell.redirection.emptyFile = false;
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
    commands.demo = {
      deny.child = semanticCommand [ "-x" ];
      optionSyntax.child = semanticCommand [ "-y" ];
    };
  };
  guardedDsl = (import ./rule-dsl.nix { inherit lib; }).guarded;
  fixtureProfile = {
    optionSyntax.valueTaking = [ "-C" ];
    conditions.execution = [
      [
        "-x"
        "--exec"
      ]
    ];
  };
  guarded = guardedDsl fixtureProfile {
    guidance = "Use the fixture.";
    deny.execution = {
      reason = "Blocked by the fixture.";
      alternatives = [ "Use the safe fixture command." ];
    };
  };

  failsToCompile = module: !(builtins.tryEval (builtins.deepSeq (evalPolicy module) true)).success;
  failsUncheckedCompile =
    policy:
    !(builtins.tryEval (builtins.deepSeq (import ./compiler.nix ({ inherit lib; } // policy)) true))
    .success;
in
{
  testOneCommandTerminalFeedsNativeAndSemanticBackends = {
    expr = {
      nativePrefixes = map (rule: rule.argvPrefix) fixturePolicy.prefixRules;
      exact = fixturePolicy.guardPolicy.exact;
      semanticPrefixes = map (rule: rule.commandPrefix) fixturePolicy.guardPolicy.semantic;
      semanticGuidance = map (rule: rule.guidance or null) fixturePolicy.guardPolicy.semantic;
      codexHasForbidden = lib.hasInfix ''decision = "forbidden"'' fixturePolicy.codexRulesContent;
    };
    expected = {
      nativePrefixes = [
        [ "fd" ]
        [
          "gh"
          "pr"
          "create"
        ]
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
      ];
      exact = [
        {
          argvPrefix = [ "remove" ];
          decision = "deny";
          reason = "Forbidden by the shared agent command policy: remove.";
        }
      ];
      semanticPrefixes = [
        [ "fd" ]
        [
          "gh"
          "pr"
          "create"
        ]
      ];
      semanticGuidance = [
        "Use the fixture."
        null
      ];
      codexHasForbidden = false;
    };
  };

  testSemanticMarkerNamesRemainOrdinaryCommandTokens = {
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

  testRuleDslExpandsNamedConditionsToCompilerInput = {
    expr = guarded;
    expected = {
      decision = true;
      guidance = "Use the fixture.";
      optionSyntax = {
        valueTaking = [ "-C" ];
        optionalEquals = [ ];
      };
      deny = [
        {
          when.options.all = [
            [
              "-x"
              "--exec"
            ]
          ];
          reason = "Blocked by the fixture.";
          alternatives = [ "Use the safe fixture command." ];
        }
      ];
    };
  };

  testRuleDslRejectsUnknownNamedConditions = {
    expr =
      !(builtins.tryEval (
        builtins.deepSeq (guardedDsl fixtureProfile {
          deny.missing = {
            reason = "Blocked by the fixture.";
            alternatives = [ "Use the safe fixture command." ];
          };
        }) true
      )).success;
    expected = true;
  };

  testShellfirmSelectorPrecedenceDataIsPreserved = {
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

  testGeneratedPolicyKeepsFailClosedBehaviorVersioned = {
    expr = {
      inherit (fixturePolicy.guardPolicy) schemaVersion unknown;
      shell = fixturePolicy.guardPolicy.shell;
    };
    expected = {
      schemaVersion = 2;
      shell.redirection.emptyFile = false;
      unknown = {
        parseError = "deny";
        dynamicExecutable = "deny";
        dynamicRelevantOption = "deny";
        maxDecodeDepth = 8;
      };
    };
  };

  testRepositoryPolicyKeepsRecoverableTrashBoundary = {
    expr = {
      nativeTrash =
        lib.all (prefix: lib.elem prefix (map (rule: rule.argvPrefix) actualPolicy.prefixRules))
          [
            [ "trash" ]
            [ "trash-list" ]
            [ "trash-put" ]
            [ "trash-restore" ]
          ];
      exactDenied = map (rule: rule.argvPrefix) actualPolicy.guardPolicy.exact;
      semanticCommands = map (rule: rule.commandPrefix) actualPolicy.guardPolicy.semantic;
      flushRule = actualPolicy.guardPolicy.shellfirm.rules."fs:flush_file_content";
    };
    expected = {
      nativeTrash = true;
      exactDenied = [
        [ "trash-empty" ]
        [ "trash-rm" ]
      ];
      semanticCommands = [
        [ "fd" ]
        [ "rm" ]
        [ "trash-restore" ]
      ];
      flushRule = false;
    };
  };

  testCompilerRejectsInvalidCommandBoundaries = {
    expr = [
      (failsToCompile { commands."*" = true; })
      (failsToCompile { commands.safe."two words" = true; })
      (failsUncheckedCompile {
        commands.demo = {
          decision = true;
          optionSyntax = { };
          deny = [ ];
        };
      })
      (failsUncheckedCompile {
        commands.demo = (semanticCommand [ "-x" ]) // {
          guidance = "";
        };
      })
    ];
    expected = [
      true
      true
      true
      true
    ];
  };

  testCompilerRejectsEmptyAndUnimplementedShellPolicies = {
    expr = [
      (failsToCompile { })
      (failsUncheckedCompile {
        commands.safe = true;
        shell.process.substitution = true;
      })
    ];
    expected = [
      true
      true
    ];
  };
}
