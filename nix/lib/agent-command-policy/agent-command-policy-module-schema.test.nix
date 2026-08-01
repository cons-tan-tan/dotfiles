# command policy moduleのmerge境界と不正なshapeの拒否を確認する。
{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./options.nix ] ++ modules;
    };

  failsToEvaluate =
    modules: !(builtins.tryEval (builtins.deepSeq (eval modules).config true)).success;

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

  evaluated = eval [
    {
      agentCommandPolicy = {
        commands.gh.issue.list = true;
        commands.fd = semanticCommand "-x";
        shell.redirection.emptyFile = false;
        shellfirm.categories.git = true;
      };
    }
    {
      agentCommandPolicy = {
        commands.gh.pr.view = true;
        shellfirm = {
          categories.fs = true;
          ruleNamespaces.git-strict = false;
          rules.git.force_push = false;
        };
      };
    }
  ];
in
{
  testCommandPolicyMergesIndependentRecursiveBranches = {
    expr = {
      inherit (evaluated.config.agentCommandPolicy.commands.gh) issue pr;
      fdDecision = evaluated.config.agentCommandPolicy.commands.fd.decision;
      categories = builtins.attrNames evaluated.config.agentCommandPolicy.shellfirm.categories;
    };
    expected = {
      issue.list = true;
      pr.view = true;
      fdDecision = true;
      categories = [
        "fs"
        "git"
      ];
    };
  };

  testCommandPolicyRejectsUnknownTopLevelField = {
    expr = failsToEvaluate [
      { agentCommandPolicy.commandz.rg = true; }
    ];
    expected = true;
  };

  testCommandPolicyRejectsInvalidCommandLeavesAndTerminals = {
    expr = map failsToEvaluate [
      [ { agentCommandPolicy.commands.demo = "allow"; } ]
      [ { agentCommandPolicy.commands.demo = { }; } ]
      [ { agentCommandPolicy.commands.demo.decision = true; } ]
      [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            decision = "allow";
          };
        }
      ]
      [
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
      ]
      [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            guidance = "   ";
          };
        }
      ]
      [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            child = true;
          };
        }
      ]
      [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "-x") // {
            deny = [ ];
          };
        }
      ]
      [
        {
          agentCommandPolicy.commands.demo = (semanticCommand "--");
        }
      ]
    ];
    expected = [
      true
      true
      true
      true
      true
      true
      true
      true
      true
    ];
  };

  testCommandPolicyRejectsInvalidShellfirmSelectors = {
    expr = map failsToEvaluate [
      [ { agentCommandPolicy.shellfirm.minimumSeverity = "Extreme"; } ]
      [ { agentCommandPolicy.shellfirm.categories.git = "true"; } ]
      [ { agentCommandPolicy.shellfirm.ruleNamespaces."bad:name" = false; } ]
      [ { agentCommandPolicy.shellfirm.rules.git.force_push = "false"; } ]
      [ { agentCommandPolicy.shellfirm.rules.git = { }; } ]
      [ { agentCommandPolicy.shellfirm.rules.force_push = false; } ]
    ];
    expected = [
      true
      true
      true
      true
      true
      true
    ];
  };

  testCommandPolicyRejectsUnimplementedShellLeaves = {
    expr = map failsToEvaluate [
      [ { agentCommandPolicy.shell.redirection = { }; } ]
      [ { agentCommandPolicy.shell.redirection.emptyFile = "false"; } ]
      [ { agentCommandPolicy.shell.process.substitution = true; } ]
      [
        { agentCommandPolicy.shell.redirection = false; }
        { agentCommandPolicy.shell.redirection.emptyFile = false; }
      ]
    ];
    expected = [
      true
      true
      true
      true
    ];
  };

  testCommandPolicyRejectsLeafBranchConflicts = {
    expr = map failsToEvaluate [
      [
        { agentCommandPolicy.commands.tool = true; }
        { agentCommandPolicy.commands.tool.safe = true; }
      ]
      [
        { agentCommandPolicy.shellfirm.rules.git = true; }
        { agentCommandPolicy.shellfirm.rules.git.force_push = false; }
      ]
    ];
    expected = [
      true
      true
    ];
  };
}
