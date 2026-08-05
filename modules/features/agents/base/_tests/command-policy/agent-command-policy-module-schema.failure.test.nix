{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  optionsModule = repoRoot + "/modules/features/agents/base/_interface/command-policy-options.nix";
  eval =
    modules:
    lib.evalModules {
      modules = [ optionsModule ] ++ modules;
    };

  denyRule = option: {
    when.options.all = [ [ option ] ];
    reason = "Blocked by the fixture.";
    alternatives = [ "Use the safe fixture command." ];
  };

  semanticCommand = option: {
    decision = true;
    optionSyntax = {
      valueTaking = [ "-C" ];
      optionalEquals = [ ];
    };
    deny = [ (denyRule option) ];
  };

  evaluate = modules: builtins.deepSeq (eval modules).config true;
  commandTreeDiagnostic = "agentCommandPolicy.commands must be a recursive command tree with boolean leaves or valid decision terminals";
  shellfirmRuleDiagnostic = "agentCommandPolicy.shellfirm.rules must contain namespace and rule tokens before boolean leaves";
  shellDiagnostic = "agentCommandPolicy.shell supports only the boolean leaf redirection.emptyFile";

  cases = {
    unknownTopLevelOption = {
      expression = evaluate [
        { agentCommandPolicy.commandz.rg = true; }
      ];
      expectedFragment = "agentCommandPolicy.commandz";
    };

    stringCommandLeaf = {
      expression = evaluate [
        { agentCommandPolicy.commands.demo = "allow"; }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    emptyCommandBranch = {
      expression = evaluate [
        { agentCommandPolicy.commands.demo = { }; }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    terminalMissingDeny = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = {
            decision = true;
            optionSyntax = {
              valueTaking = [ ];
              optionalEquals = [ ];
            };
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    terminalMissingOptionSyntax = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = {
            decision = true;
            deny = [ (denyRule "-x") ];
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    nonBooleanTerminalDecision = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            decision = "allow";
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    blankTerminalDenyReason = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            deny = [
              {
                when.options.all = [ [ "-x" ] ];
                reason = "   ";
                alternatives = [ "safe" ];
              }
            ];
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    blankTerminalGuidance = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            guidance = "   ";
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    terminalWithChildField = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            child = true;
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    terminalWithEmptyDenyRules = {
      expression = evaluate [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            deny = [ ];
          };
        }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    invalidTerminalOptionAlias = {
      expression = evaluate [
        { agentCommandPolicy.commands.demo = semanticCommand "--"; }
      ];
      expectedFragment = commandTreeDiagnostic;
    };

    unsupportedShellfirmSeverity = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.minimumSeverity = "Extreme"; }
      ];
      expectedFragment = "agentCommandPolicy.shellfirm.minimumSeverity";
    };

    nonBooleanShellfirmCategoryDecision = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.categories.git = "true"; }
      ];
      expectedFragment = "agentCommandPolicy.shellfirm.categories.git";
    };

    invalidShellfirmNamespaceSelector = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.ruleNamespaces."bad:name" = false; }
      ];
      expectedFragment = "agentCommandPolicy.shellfirm.ruleNamespaces has an invalid selector token";
    };

    nonBooleanShellfirmRuleDecision = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.rules.git.force_push = "false"; }
      ];
      expectedFragment = shellfirmRuleDiagnostic;
    };

    emptyShellfirmRuleBranch = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.rules.git = { }; }
      ];
      expectedFragment = shellfirmRuleDiagnostic;
    };

    shellfirmRuleWithoutNamespace = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.rules.force_push = false; }
      ];
      expectedFragment = shellfirmRuleDiagnostic;
    };

    emptyShellRedirectionBranch = {
      expression = evaluate [
        { agentCommandPolicy.shell.redirection = { }; }
      ];
      expectedFragment = shellDiagnostic;
    };

    nonBooleanEmptyFileDecision = {
      expression = evaluate [
        { agentCommandPolicy.shell.redirection.emptyFile = "false"; }
      ];
      expectedFragment = shellDiagnostic;
    };

    unsupportedShellProcessSubstitution = {
      expression = evaluate [
        { agentCommandPolicy.shell.process.substitution = true; }
      ];
      expectedFragment = shellDiagnostic;
    };

    shellLeafBranchConflict = {
      expression = evaluate [
        { agentCommandPolicy.shell.redirection = false; }
        { agentCommandPolicy.shell.redirection.emptyFile = false; }
      ];
      expectedFragment = "agentCommandPolicy.shell.redirection";
    };

    commandLeafBranchConflict = {
      expression = evaluate [
        { agentCommandPolicy.commands.tool = true; }
        { agentCommandPolicy.commands.tool.safe = true; }
      ];
      expectedFragment = "agentCommandPolicy.commands.tool";
    };

    shellfirmLeafBranchConflict = {
      expression = evaluate [
        { agentCommandPolicy.shellfirm.rules.git = true; }
        { agentCommandPolicy.shellfirm.rules.git.force_push = false; }
      ];
      expectedFragment = "agentCommandPolicy.shellfirm.rules.git";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
