# agent-command-policy rule schemaが誤った宣言を拒否することを検証する。
{ lib }:
let
  eval =
    modules:
    lib.evalModules {
      modules = [ ./options.nix ] ++ modules;
    };

  failsToEvaluate =
    modules: !(builtins.tryEval (builtins.deepSeq (eval modules).config true)).success;

in
{
  testCommandPolicyRejectsUnknownMatchField = {
    expr = failsToEvaluate [
      {
        agentCommandPolicy.rules = [
          {
            match = {
              commands = [ "demo" ];
              argvGroupps.demo.typo = [ ];
            };
            decision = "allow";
            justification = "Demo policy.";
          }
        ];
      }
    ];
    expected = true;
  };

  testCommandPolicyRejectsEmptyArgvGroups = {
    expr = failsToEvaluate [
      {
        agentCommandPolicy.rules = [
          {
            match.argvGroups.gh = { };
            decision = "allow";
            justification = "Empty argv group fixture.";
          }
        ];
      }
    ];
    expected = true;
  };

  testCommandPolicyRejectsTokensThatCannotBeProjectedSafely = {
    expr =
      map
        (
          match:
          failsToEvaluate [
            {
              agentCommandPolicy.rules = [
                {
                  inherit match;
                  decision = "allow";
                  justification = "Unsafe argv token fixture.";
                }
              ];
            }
          ]
        )
        [
          { commands = [ "*" ]; }
          { commands = [ "FOO=bar" ]; }
          { argvGroups."*".safe = [ ]; }
          { argvGroups."FOO=bar".safe = [ ]; }
          { argvGroups.safe."two words" = [ ]; }
          { argvGroups.safe.group = [ "two words" ]; }
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

  testCommandPolicyRejectsInvalidDecision = {
    expr = failsToEvaluate [
      {
        agentCommandPolicy.rules = [
          {
            match.commands = [ "demo" ];
            decision = "permit";
            justification = "Demo policy.";
          }
        ];
      }
    ];
    expected = true;
  };

  testCommandPolicyRejectsInvalidCommandOptions = {
    expr =
      map
        (
          commandOption:
          failsToEvaluate [
            {
              agentCommandPolicy.rules = [
                {
                  match.commandOptions.fd = [ commandOption ];
                  decision = "forbidden";
                  justification = "Invalid command option fixture.";
                }
              ];
            }
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
}
