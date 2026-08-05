{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  policyRoot = repoRoot + "/modules/features/agents/base/_lib/command-policy";
  optionsModule = repoRoot + "/modules/features/agents/base/_interface/command-policy-options.nix";

  evalPolicy =
    module:
    let
      evaluated = lib.evalModules {
        modules = [
          optionsModule
          { agentCommandPolicy = module; }
        ];
      };
      policy = evaluated.config.agentCommandPolicy;
    in
    import (policyRoot + "/compiler.nix") {
      inherit lib;
      inherit (policy)
        commands
        shell
        shellfirm
        ;
    };

  compileUnchecked = policy: import (policyRoot + "/compiler.nix") ({ inherit lib; } // policy);

  denyRule = aliases: {
    when.options.all = [ aliases ];
    reason = "Blocked by the fixture.";
    alternatives = [ "Use the safe fixture command." ];
  };

  semanticCommand = aliases: {
    decision = true;
    optionSyntax = {
      valueTaking = [ "-C" ];
      optionalEquals = [ ];
    };
    deny = [ (denyRule aliases) ];
  };

  validShellfirm = {
    enabled = false;
    minimumSeverity = "High";
    categories = { };
    ruleNamespaces = { };
    rules = { };
  };

  force = value: builtins.deepSeq value true;
  commandTreeDiagnostic = "agentCommandPolicy.commands must be a recursive command tree with boolean leaves or valid decision terminals";

  cases = {
    unknownRuleDslCondition = {
      expression =
        let
          guardedDsl = (import (policyRoot + "/rule-dsl.nix") { inherit lib; }).guarded;
        in
        force (
          guardedDsl
            {
              optionSyntax.valueTaking = [ "-C" ];
              conditions.execution = [ [ "-x" ] ];
            }
            {
              deny.missing = {
                reason = "Blocked by the fixture.";
                alternatives = [ "Use the safe fixture command." ];
              };
            }
        );
      expectedFragment = "command profile has no condition named missing";
    };

    checkedWildcardExecutableToken = {
      expression = force (evalPolicy {
        commands."*" = true;
      });
      expectedFragment = commandTreeDiagnostic;
    };

    checkedWhitespaceArgumentToken = {
      expression = force (evalPolicy {
        commands.safe."two words" = true;
      });
      expectedFragment = commandTreeDiagnostic;
    };

    uncheckedEmptyTerminalDenyRules = {
      expression = force (compileUnchecked {
        commands.demo = {
          decision = true;
          optionSyntax = { };
          deny = [ ];
        };
      });
      expectedFragment = "agent command policy command terminal is invalid";
    };

    uncheckedBlankTerminalGuidance = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          guidance = "";
        };
      });
      expectedFragment = "agent command policy command guidance must be non-empty";
    };

    uncheckedBlankDenyReason = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          deny = [
            ((denyRule [ "-x" ]) // { reason = " "; })
          ];
        };
      });
      expectedFragment = "agent command policy semantic deny reason must be non-empty";
    };

    uncheckedOverlappingOptionAliases = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          optionSyntax = {
            valueTaking = [ "-C" ];
            optionalEquals = [ "-C" ];
          };
        };
      });
      expectedFragment = "agent command policy semantic option aliases must not overlap";
    };

    uncheckedDuplicateDenyAliases = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          deny = [
            (
              (denyRule [ "-x" ])
              // {
                when.options.all = [
                  [ "-x" ]
                  [ "-x" ]
                ];
              }
            )
          ];
        };
      });
      expectedFragment = "agent command policy semantic deny option aliases must be unique";
    };

    uncheckedInvalidShellfirmCategorySelector = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          categories."bad:name" = true;
        };
      });
      expectedFragment = "agent command policy Shellfirm categories has an invalid selector";
    };

    uncheckedNonBooleanShellfirmCategoryDecision = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          categories.git = "true";
        };
      });
      expectedFragment = "agent command policy Shellfirm categories leaves must be boolean";
    };

    uncheckedInvalidShellfirmRuleToken = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          rules."bad:name".force_push = false;
        };
      });
      expectedFragment = "agent command policy has an invalid Shellfirm rule token";
    };

    uncheckedEmptyShellfirmRuleBranch = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          rules.git = { };
        };
      });
      expectedFragment = "agent command policy Shellfirm rule branch must not be empty";
    };

    uncheckedShellfirmRuleWithoutNamespace = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          rules.force_push = false;
        };
      });
      expectedFragment = "agent command policy Shellfirm rules require namespace and rule tokens";
    };

    uncheckedNonBooleanShellfirmRuleDecision = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          rules.git.force_push = "false";
        };
      });
      expectedFragment = "agent command policy Shellfirm rule leaves must be boolean";
    };

    checkedPolicyWithoutDecision = {
      expression = force (evalPolicy { });
      expectedFragment = "agent command policy must define at least one decision";
    };

    uncheckedUnsupportedShellProcessSubstitution = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shell.process.substitution = true;
      });
      expectedFragment = "agentCommandPolicy.shell supports only the boolean leaf redirection.emptyFile";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
