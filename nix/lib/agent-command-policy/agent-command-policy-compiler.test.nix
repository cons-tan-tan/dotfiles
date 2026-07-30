# 再帰agent-command-policyの正規化、backend投影、意味検証を確認する。
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
      inherit (policy) argv options;
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
    options.fd = {
      "--exec" = false;
      "-x" = false;
    };
  };

  failsToCompile = module: !(builtins.tryEval (builtins.deepSeq (evalPolicy module) true)).success;

  failsUncheckedCompile =
    policy:
    !(builtins.tryEval (
      builtins.deepSeq (import ./compiler.nix {
        inherit lib;
        inherit (policy) argv options;
      }) true
    )).success;
in
{
  testRecursiveArgvTreeProjectsToClaude = {
    expr = fixturePolicy.mkClaudePermissions { };
    expected = {
      allow = [
        "Bash(lookup exact *)"
        "Bash(lookup group deep path *)"
        "Bash(lookup group first *)"
        "Bash(lookup group second *)"
      ];
      deny = [ "Bash(remove *)" ];
    };
  };

  testRecursiveArgvTreeProjectsToCodexPrefixes = {
    expr = map (rule: rule.argvPrefix) fixturePolicy.prefixRules;
    expected = [
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
      [ "remove" ]
    ];
  };

  testCodexRulesIncludeGeneratedReasonAndMatchContracts = {
    expr =
      lib.hasInfix ''name = "lookup"'' fixturePolicy.codexRulesContent
      && lib.hasInfix ''justification = "Allowed by the shared agent command policy: lookup exact."'' fixturePolicy.codexRulesContent
      && lib.hasInfix ''match = ["lookup exact __codex_rule_probe__"]'' fixturePolicy.codexRulesContent
      && lib.hasInfix ''not_match = ["__codex_rule_probe__ lookup exact"]'' fixturePolicy.codexRulesContent;
    expected = true;
  };

  testOptionDecisionsProjectToTheSharedWrapperOnly = {
    expr = {
      forbiddenOptions = fixturePolicy.fdForbiddenOptions;
      hasFdPrefix = lib.any (rule: builtins.head rule.argvPrefix == "fd") fixturePolicy.prefixRules;
    };
    expected = {
      forbiddenOptions = [
        "--exec"
        "-x"
      ];
      hasFdPrefix = false;
    };
  };

  testCompilerProjectsMixedDecisionsForOneExecutable = {
    expr =
      map
        (rule: {
          inherit (rule) argvPrefix decision;
        })
        (evalPolicy {
          argv.tool = {
            danger = false;
            safe = true;
          };
        }).prefixRules;
    expected = [
      {
        argvPrefix = [
          "tool"
          "danger"
        ];
        decision = "forbidden";
      }
      {
        argvPrefix = [
          "tool"
          "safe"
        ];
        decision = "allow";
      }
    ];
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

  testCompilerRejectsAnEmptyArgvBranch = {
    expr = failsToCompile { argv.gh = { }; };
    expected = true;
  };

  testCompilerBoundaryRejectsNonBooleanLeaves = {
    expr = failsUncheckedCompile {
      argv.safe = "allow";
      options = { };
    };
    expected = true;
  };

  testSelectingOptionProjectionStillValidatesArgvTree = {
    expr =
      !(builtins.tryEval (
        builtins.deepSeq
          (import ./compiler.nix {
            inherit lib;
            argv."*" = true;
            options.fd."--exec" = false;
          }).fdForbiddenOptions
          true
      )).success;
    expected = true;
  };

  testCompilerRejectsUnsupportedOptionDecisions = {
    expr = [
      (failsToCompile { options.tool."--unsafe" = false; })
      (failsUncheckedCompile {
        argv = { };
        options.fd."--exec" = true;
      })
    ];
    expected = [
      true
      true
    ];
  };
}
