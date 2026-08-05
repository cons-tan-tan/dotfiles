{ lib }:
entries:
let
  isNonBlankString =
    value: builtins.isString value && value != "" && builtins.match "^[[:space:]]*$" value == null;
  allowedEntryAttrs = [
    "policy"
    "source"
  ];
  allowedPolicyAttrs = [
    "commands"
    "shell"
    "shellfirm"
  ];
  duplicates =
    values:
    builtins.filter (
      value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
    ) (lib.unique values);
  validateEntry =
    entry:
    assert lib.assertMsg (builtins.isAttrs entry) "agent-command-policy entries must be attribute sets";
    assert lib.assertMsg (lib.all (name: lib.elem name allowedEntryAttrs) (
      builtins.attrNames entry
    )) "agent-command-policy entries support only source and policy";
    assert lib.assertMsg (
      entry ? source && isNonBlankString entry.source
    ) "agent-command-policy entries require a non-blank source";
    assert lib.assertMsg (
      entry ? policy && builtins.isAttrs entry.policy && entry.policy != { }
    ) "agent-command-policy.${entry.source}.policy must be a non-empty attribute set";
    assert lib.assertMsg (lib.all (name: lib.elem name allowedPolicyAttrs) (
      builtins.attrNames entry.policy
    )) "agent-command-policy.${entry.source}.policy contains an unknown top-level field";
    entry;
  # The same named aspect may be reached through multiple include paths.
  # Identical contributions are one owner; differing policies under one source
  # remain an ownership error.
  checked = lib.unique (map validateEntry entries);
  sources = map (entry: entry.source) checked;
  isSemanticCommand =
    path: value: path != [ ] && builtins.head path == "commands" && value ? decision;
  ownedLeaves =
    source: path: value:
    if builtins.isAttrs value && !isSemanticCommand path value then
      lib.concatMap (name: ownedLeaves source (path ++ [ name ]) value.${name}) (builtins.attrNames value)
    else
      [
        {
          inherit path source;
        }
      ];
  ownership = lib.concatMap (entry: ownedLeaves entry.source [ ] entry.policy) checked;
  isPrefix =
    left: right:
    builtins.length left <= builtins.length right && lib.take (builtins.length left) right == left;
  conflicts = lib.concatMap (
    left:
    map
      (right: {
        path = if builtins.length left.path <= builtins.length right.path then left.path else right.path;
        sources = [
          left.source
          right.source
        ];
      })
      (
        builtins.filter (
          right:
          left.source < right.source && (isPrefix left.path right.path || isPrefix right.path left.path)
        ) ownership
      )
  ) ownership;
  formatConflict =
    conflict:
    "${lib.concatStringsSep "." conflict.path} (${lib.concatStringsSep " and " conflict.sources})";
in
assert lib.assertMsg (duplicates sources == [ ])
  "agent-command-policy contains duplicate sources: ${lib.concatStringsSep ", " (duplicates sources)}";
assert lib.assertMsg (lib.all (
  entry: ownedLeaves entry.source [ ] entry.policy != [ ]
) checked) "agent-command-policy fragments must own at least one policy leaf";
assert lib.assertMsg (conflicts == [ ])
  "agent-command-policy ownership conflicts: ${lib.concatStringsSep ", " (map formatConflict conflicts)}";
{
  inherit sources;
  modules = map (entry: {
    _file = "agent command policy contribution from ${entry.source}";
    config.agentCommandPolicy = entry.policy;
  }) checked;
}
