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
  evaluate = modules: builtins.deepSeq (eval modules).config true;
  cases = {
    unknownTopLevelOption = {
      expression = evaluate [
        { agentCommandPolicy.commandz.rg = true; }
      ];
      expectedFragment = "agentCommandPolicy.commandz";
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
