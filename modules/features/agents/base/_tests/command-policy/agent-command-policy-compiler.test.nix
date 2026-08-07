# 単一command treeからnative allowと共通guardが一貫して生成されることを確認する。
{ lib }:
let
  evalPolicy =
    module:
    let
      evaluated = lib.evalModules {
        modules = [
          ../../_interface/command-policy-options.nix
          { agentCommandPolicy = module; }
        ];
      };
      policy = evaluated.config.agentCommandPolicy;
    in
    import ../../_lib/command-policy/compiler.nix {
      inherit lib;
      inherit (policy)
        commands
        shell
        shellfirm
        ;
    };

  compileUnchecked =
    policy: import ../../_lib/command-policy/compiler.nix ({ inherit lib; } // policy);

  shellfirmDefaults = {
    enabled = false;
    minimumSeverity = "High";
    categories = { };
    ruleNamespaces = { };
    rules = { };
  };

  defaultShellfirmPolicy = compileUnchecked {
    commands.safe = true;
  };

  categoryOnlyPolicy = compileUnchecked {
    commands = { };
    shellfirm = shellfirmDefaults // {
      enabled = true;
      categories.git = true;
    };
  };

  namespaceOnlyPolicy = compileUnchecked {
    commands = { };
    shellfirm = shellfirmDefaults // {
      enabled = true;
      ruleNamespaces.git = true;
    };
  };

  ruleOnlyPolicy = compileUnchecked {
    commands = { };
    shellfirm = shellfirmDefaults // {
      enabled = true;
      rules.git.force_push = true;
    };
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

  markerNamePolicy = evalPolicy {
    commands.demo = {
      deny.child = semanticCommand [ "-x" ];
      optionSyntax.child = semanticCommand [ "-y" ];
    };
  };
  guardedDsl = (import ../../_lib/command-policy/rule-dsl.nix { inherit lib; }).guarded;
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

  testDefaultShellfirmRemainsDisabledForPrefixOnlyPolicy = {
    expr = defaultShellfirmPolicy.guardPolicy.shellfirm;
    expected = shellfirmDefaults;
  };

  testEachShellfirmSelectorSourceCanProvideTheOnlyDecision = {
    expr = map (policy: policy.guardPolicy.shellfirm.enabled) [
      categoryOnlyPolicy
      namespaceOnlyPolicy
      ruleOnlyPolicy
    ];
    expected = [
      true
      true
      true
    ];
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

}
