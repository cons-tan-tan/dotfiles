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
  compileDenyRule =
    rule:
    force (compileUnchecked {
      commands.demo = (semanticCommand [ "-x" ]) // {
        deny = [ rule ];
      };
    });
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

    uncheckedExecutableTokenUsingArgumentOnlySyntax = {
      expression = force (compileUnchecked {
        commands."safe/path" = true;
      });
      expectedFragment = "agent command policy has an invalid command token";
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

    uncheckedNonBooleanTerminalDecision = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          decision = "allow";
        };
      });
      expectedFragment = "agent command policy command terminal is invalid";
    };

    uncheckedTerminalWithUnknownField = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          unexpected = true;
        };
      });
      expectedFragment = "agent command policy command terminal is invalid";
    };

    uncheckedTerminalWithoutDeny = {
      expression = force (compileUnchecked {
        commands.demo = removeAttrs (semanticCommand [ "-x" ]) [ "deny" ];
      });
      expectedFragment = "agent command policy command terminal is invalid";
    };

    uncheckedTerminalWithoutOptionSyntax = {
      expression = force (compileUnchecked {
        commands.demo = removeAttrs (semanticCommand [ "-x" ]) [ "optionSyntax" ];
      });
      expectedFragment = "agent command policy command terminal is invalid";
    };

    uncheckedTerminalWithNonListDeny = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          deny = "deny";
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

    uncheckedOptionListIsNotAList = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          optionSyntax.valueTaking = "-C";
        };
      });
      expectedFragment = "agent command policy semantic optionSyntax.valueTaking must contain valid command options";
    };

    uncheckedOptionListContainsInvalidSyntax = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          optionSyntax.valueTaking = [ "not an option" ];
        };
      });
      expectedFragment = "agent command policy semantic optionSyntax.valueTaking must contain valid command options";
    };

    uncheckedOptionSyntaxHasUnknownField = {
      expression = force (compileUnchecked {
        commands.demo = (semanticCommand [ "-x" ]) // {
          optionSyntax.unexpected = [ ];
        };
      });
      expectedFragment = "agent command policy semantic optionSyntax is invalid";
    };

    uncheckedDenyRuleIsNotAnAttributeSet = {
      expression = compileDenyRule "deny";
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyRuleHasUnknownField = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { unexpected = true; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyRuleWithoutWhen = {
      expression = compileDenyRule (removeAttrs (denyRule [ "-x" ]) [ "when" ]);
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyWhenIsNotAnAttributeSet = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { when = "always"; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyWhenHasUnknownField = {
      expression = compileDenyRule (
        (denyRule [ "-x" ])
        // {
          when = (denyRule [ "-x" ]).when // {
            unexpected = true;
          };
        }
      );
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyWhenWithoutOptions = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { when = { }; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyOptionsIsNotAnAttributeSet = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { when.options = "-x"; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyOptionsHasUnknownField = {
      expression = compileDenyRule (
        (denyRule [ "-x" ])
        // {
          when.options = (denyRule [ "-x" ]).when.options // {
            unexpected = true;
          };
        }
      );
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyOptionsWithoutAll = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { when.options = { }; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyAllIsNotAList = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { when.options.all = "-x"; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
    };

    uncheckedDenyAllIsEmpty = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { when.options.all = [ ]; });
      expectedFragment = "agent command policy semantic deny condition is invalid";
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

    uncheckedDenyRuleWithoutAlternatives = {
      expression = compileDenyRule (removeAttrs (denyRule [ "-x" ]) [ "alternatives" ]);
      expectedFragment = "agent command policy semantic deny alternatives are invalid";
    };

    uncheckedDenyAlternativesIsNotAList = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { alternatives = "Use the safe command."; });
      expectedFragment = "agent command policy semantic deny alternatives are invalid";
    };

    uncheckedDenyAlternativesIsEmpty = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { alternatives = [ ]; });
      expectedFragment = "agent command policy semantic deny alternatives are invalid";
    };

    uncheckedDenyAlternativeIsBlank = {
      expression = compileDenyRule ((denyRule [ "-x" ]) // { alternatives = [ " " ]; });
      expectedFragment = "agent command policy semantic deny alternatives are invalid";
    };

    uncheckedDenyAlternativesAreDuplicated = {
      expression = compileDenyRule (
        (denyRule [ "-x" ])
        // {
          alternatives = [
            "Use the safe command."
            "Use the safe command."
          ];
        }
      );
      expectedFragment = "agent command policy semantic deny alternatives are invalid";
    };

    uncheckedShellfirmHasUnknownField = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          unexpected = true;
        };
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithoutEnabled = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = removeAttrs validShellfirm [ "enabled" ];
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithNonBooleanEnabled = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          enabled = "false";
        };
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithoutMinimumSeverity = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = removeAttrs validShellfirm [ "minimumSeverity" ];
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithInvalidMinimumSeverity = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = validShellfirm // {
          minimumSeverity = "Emergency";
        };
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithoutCategories = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = removeAttrs validShellfirm [ "categories" ];
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithoutRuleNamespaces = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = removeAttrs validShellfirm [ "ruleNamespaces" ];
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
    };

    uncheckedShellfirmWithoutRules = {
      expression = force (compileUnchecked {
        commands.safe = true;
        shellfirm = removeAttrs validShellfirm [ "rules" ];
      });
      expectedFragment = "agent command policy Shellfirm configuration is invalid";
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

    uncheckedDisabledShellfirmSelectorWithoutOtherDecision = {
      expression = force (compileUnchecked {
        commands = { };
        shellfirm = validShellfirm // {
          categories.git = true;
        };
      });
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
