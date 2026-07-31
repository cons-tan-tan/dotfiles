# command policyの再帰treeとsemantic guard selectorのNix module schema。
{ lib, ... }:
let
  inherit (lib) mkOption types;

  executableTokenPattern = "^[a-zA-Z0-9_][a-zA-Z0-9_+@%.-]*$";
  commandOptionPattern = "^(--[a-zA-Z0-9][a-zA-Z0-9-]*|-[a-zA-Z0-9])$";

  isExecutableToken = value: builtins.match executableTokenPattern value != null;
  isCommandOption = value: builtins.match commandOptionPattern value != null;
  isSelectorToken = value: value != "" && !lib.hasInfix ":" value;
  isNonEmptyString = value: builtins.isString value && value != "";
  isUnique = values: builtins.length values == builtins.length (lib.unique values);
  hasOnlyAttrs = allowed: value: lib.all (name: lib.elem name allowed) (builtins.attrNames value);

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
    && isNonEmptyString rule.reason
    && rule ? alternatives
    && builtins.isList rule.alternatives
    && rule.alternatives != [ ]
    && lib.all isNonEmptyString rule.alternatives
    && isUnique rule.alternatives;

  validateSemanticTree =
    tree:
    let
      validNode =
        isRoot: node:
        let
          isTerminal =
            builtins.isAttrs node
            &&
              builtins.attrNames node == [
                "deny"
                "optionSyntax"
              ]
            && builtins.isList node.deny
            && builtins.isAttrs node.optionSyntax;
        in
        builtins.isAttrs node
        && (isRoot || builtins.attrNames node != [ ])
        && (
          if isTerminal then
            validOptionSyntax node.optionSyntax && node.deny != [ ] && lib.all validDenyRule node.deny
          else
            lib.all isExecutableToken (builtins.attrNames node)
            && lib.all (value: builtins.isAttrs value && validNode false value) (builtins.attrValues node)
        );
    in
    assert lib.assertMsg (validNode true tree)
      "agentCommandPolicy.semantic must be a recursive command tree with valid optionSyntax and non-empty deny leaves";
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
        isRoot: node:
        builtins.isAttrs node
        && (isRoot || builtins.attrNames node != [ ])
        && lib.all isSelectorToken (builtins.attrNames node)
        && lib.all (value: builtins.isBool value || (builtins.isAttrs value && validNode false value)) (
          builtins.attrValues node
        );
    in
    assert lib.assertMsg (validNode true tree)
      "agentCommandPolicy.shellfirm.rules must be a recursive selector tree with boolean leaves and no empty branches";
    tree;
in
{
  options.agentCommandPolicy = {
    argv = mkOption {
      default = { };
      type = types.attrsOf types.anything;
      apply = validateArgvTree;
      description = "Recursive argv-prefix policy tree; true allows, false denies, and absence leaves the agent default.";
    };

    semantic = mkOption {
      default = { };
      type = types.attrsOf types.anything;
      apply = validateSemanticTree;
      description = "Recursive command tree for option-aware semantic deny rules.";
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
