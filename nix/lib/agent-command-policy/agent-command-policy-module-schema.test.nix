# agent-command-policy moduleが再帰treeをmergeし、誤ったshapeを拒否することを確認する。
{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./options.nix ] ++ modules;
    };

  failsToEvaluate =
    modules: !(builtins.tryEval (builtins.deepSeq (eval modules).config true)).success;

  evaluated = eval [
    {
      agentCommandPolicy = {
        argv.gh.issue.list = true;
        options.fd."--exec" = false;
      };
    }
    {
      agentCommandPolicy = {
        argv = {
          gh.pr.view = true;
          rm."-rf" = false;
        };
        options.fd."-x" = false;
      };
    }
  ];
in
{
  testCommandPolicyMergesRecursiveBranches = {
    expr = evaluated.config.agentCommandPolicy;
    expected = {
      argv = {
        gh = {
          issue.list = true;
          pr.view = true;
        };
        rm."-rf" = false;
      };
      options.fd = {
        "--exec" = false;
        "-x" = false;
      };
    };
  };

  testCommandPolicyRejectsUnknownTopLevelField = {
    expr = failsToEvaluate [
      { agentCommandPolicy.commandz.rg = true; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsNonBooleanArgvLeaves = {
    expr = failsToEvaluate [
      { agentCommandPolicy.argv.demo = "allow"; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsNonBooleanOptionLeaves = {
    expr = failsToEvaluate [
      { agentCommandPolicy.options.fd."--exec" = "false"; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsAllowedOptionLeaves = {
    expr = failsToEvaluate [
      { agentCommandPolicy.options.fd."--exec" = true; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsEmptyOptionGroups = {
    expr = failsToEvaluate [
      { agentCommandPolicy.options.fd = { }; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsInvalidOptionNames = {
    expr =
      map
        (
          option:
          failsToEvaluate [
            { agentCommandPolicy.options.fd.${option} = false; }
          ]
        )
        [
          "--"
          "-xy"
          "--ex*ec"
        ];
    expected = [
      true
      true
      true
    ];
  };

  testCommandPolicyRejectsInvalidOptionCommands = {
    expr = failsToEvaluate [
      { agentCommandPolicy.options."*"."--unsafe" = false; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsConflictingLeafDecisions = {
    expr = failsToEvaluate [
      { agentCommandPolicy.argv.tool.safe = true; }
      { agentCommandPolicy.argv.tool.safe = false; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsLeafBranchConflicts = {
    expr = failsToEvaluate [
      { agentCommandPolicy.argv.tool = true; }
      { agentCommandPolicy.argv.tool.safe = true; }
    ];
    expected = true;
  };
}
