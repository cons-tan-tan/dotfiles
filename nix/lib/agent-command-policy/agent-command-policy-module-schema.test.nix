# command policy moduleのmerge境界と不正なshapeの拒否を確認する。
{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./options.nix ] ++ modules;
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

}
