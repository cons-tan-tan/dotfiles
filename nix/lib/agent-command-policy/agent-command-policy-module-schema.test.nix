# agent-command-policy moduleが再帰treeをmergeし、不正なshapeを拒否することを確認する。
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

  evaluated = eval [
    {
      agentCommandPolicy = {
        argv.gh.issue.list = true;
        semantic.fd = {
          optionSyntax = {
            valueTaking = [ "-C" ];
            optionalEquals = [ ];
          };
          deny = [ (denyRule "-x") ];
        };
        shellfirm = {
          categories.git = true;
          ruleNamespaces.git-strict = false;
        };
      };
    }
    {
      agentCommandPolicy = {
        argv.gh.pr.view = true;
        semantic.gh.pr.create = {
          optionSyntax = {
            valueTaking = [ ];
            optionalEquals = [ ];
          };
          deny = [ (denyRule "--fill") ];
        };
        shellfirm = {
          categories.fs = true;
          rules.git.force_push = false;
        };
      };
    }
  ];
in
{
  testCommandPolicyMergesRecursiveBranches = {
    expr = evaluated.config.agentCommandPolicy;
    expected = {
      argv.gh = {
        issue.list = true;
        pr.view = true;
      };
      semantic = {
        fd = {
          optionSyntax = {
            valueTaking = [ "-C" ];
            optionalEquals = [ ];
          };
          deny = [ (denyRule "-x") ];
        };
        gh.pr.create = {
          optionSyntax = {
            valueTaking = [ ];
            optionalEquals = [ ];
          };
          deny = [ (denyRule "--fill") ];
        };
      };
      shellfirm = {
        enabled = false;
        minimumSeverity = "High";
        categories = {
          fs = true;
          git = true;
        };
        ruleNamespaces.git-strict = false;
        rules.git.force_push = false;
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

  testCommandPolicyRejectsSemanticTerminalBranchMixing = {
    expr = failsToEvaluate [
      {
        agentCommandPolicy.semantic.demo = {
          optionSyntax = {
            valueTaking = [ ];
            optionalEquals = [ ];
          };
          deny = [ (denyRule "-x") ];
          child = { };
        };
      }
    ];
    expected = true;
  };

  testCommandPolicyRejectsInvalidSemanticRules = {
    expr =
      map
        (
          semantic:
          failsToEvaluate [
            { agentCommandPolicy.semantic.demo = semantic; }
          ]
        )
        [
          {
            optionSyntax = { };
            deny = [ ];
          }
          {
            optionSyntax.valueTaking = [ "--" ];
            deny = [ (denyRule "-x") ];
          }
          {
            optionSyntax.valueTaking = [ ];
            deny = [ (denyRule "-xy") ];
          }
          {
            optionSyntax.valueTaking = [ ];
            deny = [
              {
                when.options.all = [ [ "-x" ] ];
                reason = "";
                alternatives = [ "safe" ];
              }
            ];
          }
          {
            optionSyntax.valueTaking = [ ];
            deny = [
              {
                when.options.all = [ [ "-x" ] ];
                reason = "reason";
                alternatives = [ ];
              }
            ];
          }
        ];
    expected = [
      true
      true
      true
      true
      true
    ];
  };

  testCommandPolicyRejectsInvalidShellfirmSelectors = {
    expr = [
      (failsToEvaluate [
        { agentCommandPolicy.shellfirm.minimumSeverity = "Extreme"; }
      ])
      (failsToEvaluate [
        { agentCommandPolicy.shellfirm.categories.git = "true"; }
      ])
      (failsToEvaluate [
        { agentCommandPolicy.shellfirm.ruleNamespaces."bad:name" = false; }
      ])
      (failsToEvaluate [
        { agentCommandPolicy.shellfirm.rules.git.force_push = "false"; }
      ])
      (failsToEvaluate [
        { agentCommandPolicy.shellfirm.rules.git = { }; }
      ])
    ];
    expected = [
      true
      true
      true
      true
      true
    ];
  };

  testCommandPolicyRejectsLeafBranchConflicts = {
    expr = [
      (failsToEvaluate [
        { agentCommandPolicy.argv.tool = true; }
        { agentCommandPolicy.argv.tool.safe = true; }
      ])
      (failsToEvaluate [
        { agentCommandPolicy.shellfirm.rules.git = true; }
        { agentCommandPolicy.shellfirm.rules.git.force_push = false; }
      ])
    ];
    expected = [
      true
      true
    ];
  };
}
