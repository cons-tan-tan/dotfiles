# command policy ruleのNix module schema。
{ lib, ... }:
let
  inherit (lib) mkOption types;

  nonEmptyString = types.strMatching ".+";
  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  argvTokenPattern = "^[a-zA-Z0-9_./:+@%=-]+$";
  isExecutableToken = value: builtins.match executableTokenPattern value != null;
  isArgvToken = value: builtins.match argvTokenPattern value != null;
  executableToken = types.strMatching executableTokenPattern;
  argvToken = types.strMatching argvTokenPattern;
  argvGroup = types.addCheck (types.attrsOf (types.listOf argvToken)) (
    values: builtins.attrNames values != [ ] && lib.all isArgvToken (builtins.attrNames values)
  );
  argvGroups = types.addCheck (types.attrsOf argvGroup) (
    values: lib.all isExecutableToken (builtins.attrNames values)
  );
  commandOption = types.strMatching "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";
  commandOptionList = types.addCheck (types.listOf commandOption) (values: values != [ ]);

  matchType = types.submodule {
    options = {
      commands = mkOption {
        default = [ ];
        type = types.listOf executableToken;
        description = "Executables whose invocations are matched.";
      };
      argvGroups = mkOption {
        default = { };
        type = argvGroups;
        description = "Two- or three-token argv prefixes; an empty third-token list matches the first two tokens.";
      };
      commandOptions = mkOption {
        default = { };
        type = types.attrsOf commandOptionList;
        description = "Options matched regardless of argument position, grouped by executable.";
      };
    };
  };

  ruleType = types.submodule {
    options = {
      match = mkOption {
        type = matchType;
        description = "Agent-independent command match expression.";
      };
      decision = mkOption {
        type = types.enum [
          "allow"
          "prompt"
          "forbidden"
        ];
        description = "Shared command policy decision.";
      };
      justification = mkOption {
        type = nonEmptyString;
        description = "Human-readable reason rendered into supported agent policies.";
      };
    };
  };

in
{
  options.agentCommandPolicy.rules = mkOption {
    default = [ ];
    type = types.listOf ruleType;
    description = "Agent-independent command policy rules.";
  };
}
