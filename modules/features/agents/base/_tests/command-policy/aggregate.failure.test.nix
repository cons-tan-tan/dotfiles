{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  aggregate = import (repoRoot + "/modules/features/agents/base/_lib/command-policy/aggregate.nix") {
    inherit lib;
  };
  force = entries: builtins.deepSeq (aggregate entries) true;
  cases = {
    duplicateSource = {
      expression = force [
        {
          source = "feature/same";
          policy.commands.alpha = true;
        }
        {
          source = "feature/same";
          policy.commands.beta = true;
        }
      ];
      expectedFragment = "agent-command-policy contains duplicate sources: feature/same";
    };
    exactOwnershipConflict = {
      expression = force [
        {
          source = "feature/allow";
          policy.commands.tool = true;
        }
        {
          source = "feature/deny";
          policy.commands.tool = false;
        }
      ];
      expectedFragment = "agent-command-policy ownership conflicts: commands.tool";
    };
    sameValueExactOwnershipConflict = {
      expression = force [
        {
          source = "feature/first";
          policy.commands.tool = true;
        }
        {
          source = "feature/second";
          policy.commands.tool = true;
        }
      ];
      expectedFragment = "agent-command-policy ownership conflicts: commands.tool";
    };
    prefixOwnershipConflict = {
      expression = force [
        {
          source = "feature/branch";
          policy.commands.tool.safe = true;
        }
        {
          source = "feature/leaf";
          policy.commands.tool = false;
        }
      ];
      expectedFragment = "agent-command-policy ownership conflicts: commands.tool";
    };
    unknownPolicyField = {
      expression = force [
        {
          source = "feature/unknown";
          policy.unknown = true;
        }
      ];
      expectedFragment = "policy contains an unknown top-level field";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
