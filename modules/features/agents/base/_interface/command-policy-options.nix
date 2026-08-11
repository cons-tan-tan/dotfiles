# command policyの再帰treeとsemantic guard selectorのNix module schema。
{ lib, ... }:
let
  inherit (lib) mkOption types;

  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  commandOptionPattern = "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";

  isCommandOption = value: builtins.match commandOptionPattern value != null;
  isSelectorToken = value: value != "" && !lib.hasInfix ":" value;
  isNonBlankString = value: builtins.isString value && builtins.match "^[[:space:]]*$" value == null;
  isUnique = values: builtins.length values == builtins.length (lib.unique values);
  hasOnlyAttrs = allowed: value: lib.all (name: lib.elem name allowed) (builtins.attrNames value);

  validOptionSyntax =
    value:
    builtins.isAttrs value
    && hasOnlyAttrs [
      "optionalEquals"
      "valueTaking"
    ] value
    && builtins.isList (value.valueTaking or [ ])
    && builtins.isList (value.optionalEquals or [ ])
    && lib.all isCommandOption ((value.valueTaking or [ ]) ++ (value.optionalEquals or [ ]))
    && isUnique ((value.valueTaking or [ ]) ++ (value.optionalEquals or [ ]));

  validDenyRule =
    rule:
    builtins.isAttrs rule
    && hasOnlyAttrs [
      "alternatives"
      "reason"
      "when"
    ] rule
    && rule ? when
    && builtins.isAttrs rule.when
    && hasOnlyAttrs [ "options" ] rule.when
    && rule.when ? options
    && builtins.isAttrs rule.when.options
    && hasOnlyAttrs [ "all" ] rule.when.options
    && rule.when.options ? all
    && builtins.isList rule.when.options.all
    && rule.when.options.all != [ ]
    && lib.all (
      group: builtins.isList group && group != [ ] && lib.all isCommandOption group && isUnique group
    ) rule.when.options.all
    && isUnique (lib.concatLists rule.when.options.all)
    && rule ? reason
    && isNonBlankString rule.reason
    && rule ? alternatives
    && builtins.isList rule.alternatives
    && rule.alternatives != [ ]
    && lib.all isNonBlankString rule.alternatives
    && isUnique rule.alternatives;

  validateCommandTree =
    tree:
    let
      validNode =
        isRoot: node:
        let
          isTerminal = builtins.isAttrs node && node ? decision;
        in
        builtins.isAttrs node
        && (isRoot || builtins.attrNames node != [ ])
        && (
          if isTerminal then
            node ? deny
            && node ? optionSyntax
            && hasOnlyAttrs [
              "decision"
              "deny"
              "guidance"
              "optionSyntax"
            ] node
            && builtins.isBool node.decision
            && builtins.isList node.deny
            && builtins.isAttrs node.optionSyntax
            && validOptionSyntax node.optionSyntax
            && node.deny != [ ]
            && lib.all validDenyRule node.deny
            && (!(node ? guidance) || isNonBlankString node.guidance)
          else
            lib.all (
              name:
              builtins.match (if isRoot then executableTokenPattern else "^[a-zA-Z0-9_./:+@%=-]+$") name != null
            ) (builtins.attrNames node)
            && lib.all (value: builtins.isBool value || (builtins.isAttrs value && validNode false value)) (
              builtins.attrValues node
            )
        );
    in
    assert lib.assertMsg (validNode true tree)
      "agentCommandPolicy.commands must be a recursive command tree with boolean leaves or valid decision terminals";
    tree;

  validateSelectorMap =
    label: values:
    assert lib.assertMsg (lib.all isSelectorToken (
      builtins.attrNames values
    )) "agentCommandPolicy.shellfirm.${label} has an invalid selector token";
    values;

  validateRuleTree =
    tree:
    let
      validNode =
        depth: node:
        builtins.isAttrs node
        && (depth == 0 || builtins.attrNames node != [ ])
        && lib.all isSelectorToken (builtins.attrNames node)
        && lib.all (
          value:
          (builtins.isBool value && depth >= 1) || (builtins.isAttrs value && validNode (depth + 1) value)
        ) (builtins.attrValues node);
    in
    assert lib.assertMsg (validNode 0 tree)
      "agentCommandPolicy.shellfirm.rules must contain namespace and rule tokens before boolean leaves";
    tree;

  validateShellTree =
    tree: (import ../_lib/command-policy/shell-policy-schema.nix { inherit lib; }).validate tree;
  validateCommandGrammars =
    grammars: (import ../_lib/command-policy/grammar-schema.nix { inherit lib; }).validate grammars;
in
{
  options.agentCommandPolicy = {
    commandGrammars = mkOption {
      default = { };
      type = types.attrsOf types.anything;
      apply = validateCommandGrammars;
      description = "Executable-specific selector grammars used to canonicalize guarded command paths.";
    };

    commands = mkOption {
      default = { };
      type = types.attrsOf types.anything;
      apply = validateCommandTree;
      description = "Recursive command policy; boolean leaves are decisions and decision terminals add option-aware rules.";
    };

    shell = mkOption {
      default = { };
      type = types.attrsOf types.anything;
      apply = validateShellTree;
      description = "Implemented shell-syntax policy leaves; true allows, false denies, and absence leaves the agent default.";
    };

    shellfirm = mkOption {
      default = { };
      type = types.submodule {
        options = {
          enabled = mkOption {
            default = false;
            type = types.bool;
          };
          minimumSeverity = mkOption {
            default = "High";
            type = types.enum [
              "Info"
              "Low"
              "Medium"
              "High"
              "Critical"
            ];
          };
          categories = mkOption {
            default = { };
            type = types.attrsOf types.bool;
            apply = validateSelectorMap "categories";
          };
          ruleNamespaces = mkOption {
            default = { };
            type = types.attrsOf types.bool;
            apply = validateSelectorMap "ruleNamespaces";
          };
          rules = mkOption {
            default = { };
            type = types.attrsOf types.anything;
            apply = validateRuleTree;
          };
        };
      };
      description = "Shellfirm catalog selection policy.";
    };
  };
}
