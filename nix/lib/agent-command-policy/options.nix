# command policyの再帰argv treeとoption policyのNix module schema。
{ lib, ... }:
let
  inherit (lib) mkOption types;

  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  commandOptionPattern = "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";
  isExecutableToken = value: builtins.match executableTokenPattern value != null;
  isCommandOption = value: builtins.match commandOptionPattern value != null;

  # attrsetは次のargv token、booleanはそのprefixのdecisionを表す。
  validateArgvTree =
    tree:
    let
      validNode =
        isRoot: node:
        builtins.isAttrs node
        && (isRoot || builtins.attrNames node != [ ])
        && lib.all (value: builtins.isBool value || (builtins.isAttrs value && validNode false value)) (
          builtins.attrValues node
        );
    in
    assert lib.assertMsg (validNode true tree)
      "agentCommandPolicy.argv must be a recursive attribute set with boolean leaves and no empty branches";
    tree;
  optionPolicy = types.addCheck (types.attrsOf types.bool) (
    values:
    builtins.attrNames values != [ ]
    && lib.all isCommandOption (builtins.attrNames values)
    && lib.all (decision: builtins.isBool decision && !decision) (builtins.attrValues values)
  );
  optionPolicies = types.addCheck (types.attrsOf optionPolicy) (
    values: lib.all isExecutableToken (builtins.attrNames values)
  );
in
{
  options.agentCommandPolicy = {
    argv = mkOption {
      default = { };
      # anythingはmodule間の再帰attrset mergeに使い、shapeはapplyで検証する。
      type = types.attrsOf types.anything;
      apply = validateArgvTree;
      description = "Recursive argv-prefix policy tree; true allows, false forbids, and absence leaves the agent default.";
    };

    options = mkOption {
      default = { };
      type = optionPolicies;
      description = "Parsed command options forbidden by the shared wrapper; each leaf must be false.";
    };
  };
}
