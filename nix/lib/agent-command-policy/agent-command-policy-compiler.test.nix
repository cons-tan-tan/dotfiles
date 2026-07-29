# agent-command-policy compilerの投影と意味検証を確認する。
{ lib }:
let
  evalRules =
    rules:
    (lib.evalModules {
      modules = [
        ./options.nix
        { agentCommandPolicy.rules = rules; }
      ];
    }).config.agentCommandPolicy.rules;

  fixtureRules = evalRules [
    {
      match.argvGroups.lookup = {
        exact = [ ];
        group = [
          "first"
          "second"
        ];
      };
      decision = "allow";
      justification = "Fixture allow rule.";
    }
    {
      match.commands = [ "review" ];
      decision = "prompt";
      justification = "Fixture prompt rule.";
    }
    {
      match.commands = [ "remove" ];
      decision = "forbidden";
      justification = "Fixture forbidden rule.";
    }
    {
      match.commandOptions.fd = [
        "--exec"
        "-x"
      ];
      decision = "forbidden";
      justification = "Fixture command option rule.";
    }
  ];

  fixturePolicy = import ./compiler.nix {
    inherit lib;
    rules = fixtureRules;
  };

  failsToCompile =
    rules:
    !(builtins.tryEval (
      builtins.deepSeq (import ./compiler.nix {
        inherit lib;
        rules = evalRules rules;
      }) true
    )).success;

  failsUncheckedCompile =
    rules:
    !(builtins.tryEval (
      builtins.deepSeq (import ./compiler.nix {
        inherit lib rules;
      }) true
    )).success;
in
{
  testClaudeProjectionUsesSharedMatchExpressions = {
    expr = fixturePolicy.mkClaudePermissions { };
    expected = {
      allow = [
        "Bash(lookup exact *)"
        "Bash(lookup group first *)"
        "Bash(lookup group second *)"
      ];
      ask = [ "Bash(review *)" ];
      deny = [ "Bash(remove *)" ];
    };
  };

  testCodexProjectionUsesRepresentablePrefixMatches = {
    expr = map (rule: rule.argvPrefix) fixturePolicy.prefixRules;
    expected = [
      [
        "lookup"
        "exact"
      ]
      [
        "lookup"
        "group"
        "first"
      ]
      [
        "lookup"
        "group"
        "second"
      ]
      [ "review" ]
      [ "remove" ]
    ];
  };

  testCodexRulesIncludeExecutableAndMatchContracts = {
    expr =
      lib.hasInfix ''name = "lookup"'' fixturePolicy.codexRulesContent
      && lib.hasInfix ''match = ["lookup exact __codex_rule_probe__"]'' fixturePolicy.codexRulesContent
      && lib.hasInfix ''not_match = ["__codex_rule_probe__ lookup exact"]'' fixturePolicy.codexRulesContent;
    expected = true;
  };

  testCommandOptionMatchesProjectToTheSharedWrapper = {
    expr = fixturePolicy.fdForbiddenOptions;
    expected = [
      "--exec"
      "-x"
    ];
  };

  testCompilerRejectsDuplicateSemanticMatches = {
    expr = failsToCompile [
      {
        match.commands = [ "duplicate" ];
        decision = "allow";
        justification = "First duplicate fixture.";
      }
      {
        match.commands = [ "duplicate" ];
        decision = "allow";
        justification = "Second duplicate fixture.";
      }
    ];
    expected = true;
  };

  testCompilerRejectsDuplicateCommandOptionMatches = {
    expr = failsToCompile [
      {
        match.commandOptions.fd = [
          "--exec"
          "--exec"
        ];
        decision = "forbidden";
        justification = "Duplicate command option fixture.";
      }
    ];
    expected = true;
  };

  testCompilerRejectsMixedCodexDecisionsForOneExecutable = {
    expr = failsToCompile [
      {
        match.commands = [ "tool" ];
        decision = "allow";
        justification = "Allow fixture.";
      }
      {
        match.argvGroups.tool.danger = [ ];
        decision = "forbidden";
        justification = "Forbidden fixture.";
      }
    ];
    expected = true;
  };

  testCompilerRejectsEmptyMatchExpressions = {
    expr = failsToCompile [
      {
        match = { };
        decision = "forbidden";
        justification = "Empty match fixture.";
      }
    ];
    expected = true;
  };

  testCompilerRejectsUnsafeArgvGroupKeys = {
    expr = map failsUncheckedCompile [
      [
        {
          match = {
            commands = [ ];
            argvGroups."*".safe = [ ];
            commandOptions = { };
          };
          decision = "allow";
          justification = "Unsafe executable fixture.";
        }
      ]
      [
        {
          match = {
            commands = [ ];
            argvGroups.safe."two words" = [ ];
            commandOptions = { };
          };
          decision = "allow";
          justification = "Unsafe second token fixture.";
        }
      ]
    ];
    expected = [
      true
      true
    ];
  };

  testCompilerRejectsArgvGroupsThatExpandToNoMatches = {
    expr = failsUncheckedCompile [
      {
        match = {
          commands = [ "safe" ];
          argvGroups.gh = { };
          commandOptions = { };
        };
        decision = "allow";
        justification = "Compiler boundary fixture.";
      }
    ];
    expected = true;
  };

  testCompilerRejectsUnsupportedCommandOptionMatches = {
    expr = map failsToCompile [
      [
        {
          match.commandOptions.tool = [ "--unsafe" ];
          decision = "forbidden";
          justification = "Unsupported command fixture.";
        }
      ]
      [
        {
          match.commandOptions.fd = [ "--exec" ];
          decision = "allow";
          justification = "Unsupported decision fixture.";
        }
      ]
    ];
    expected = [
      true
      true
    ];
  };
}
