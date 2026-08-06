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
    duplicateOwner = {
      expression = force [
        {
          owner = "feature/same";
          policy.commands.alpha = true;
        }
        {
          owner = "feature/same";
          policy.commands.beta = true;
        }
      ];
      expectedFragment = "agent-command-policy contains duplicate owners: feature/same";
    };
    exactOwnershipConflict = {
      expression = force [
        {
          owner = "feature/allow";
          policy.commands.tool = true;
        }
        {
          owner = "feature/deny";
          policy.commands.tool = false;
        }
      ];
      expectedFragment = "agent-command-policy ownership conflicts: commands.tool";
    };
    sameValueExactOwnershipConflict = {
      expression = force [
        {
          owner = "feature/first";
          policy.commands.tool = true;
        }
        {
          owner = "feature/second";
          policy.commands.tool = true;
        }
      ];
      expectedFragment = "agent-command-policy ownership conflicts: commands.tool";
    };
    prefixOwnershipConflict = {
      expression = force [
        {
          owner = "feature/branch";
          policy.commands.tool.safe = true;
        }
        {
          owner = "feature/leaf";
          policy.commands.tool = false;
        }
      ];
      expectedFragment = "agent-command-policy ownership conflicts: commands.tool";
    };
    unknownPolicyField = {
      expression = force [
        {
          owner = "feature/unknown";
          policy.unknown = true;
        }
      ];
      expectedFragment = "policy contains an unknown top-level field";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
