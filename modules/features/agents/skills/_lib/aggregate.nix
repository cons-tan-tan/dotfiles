{ lib }:
entries:
let
  inherit (import ./skill-policy.nix { inherit lib; }) isSkillName;
  allowedEntryAttrs = [
    "definition"
    "enable"
    "name"
    "provenance"
  ];
  validProvenance = [
    "external"
    "hcom"
    "local"
  ];
  validateEntry =
    entry:
    assert lib.assertMsg (builtins.isAttrs entry) "agent skill contributions must be attribute sets";
    assert lib.assertMsg (lib.all (name: lib.elem name allowedEntryAttrs) (
      builtins.attrNames entry
    )) "agent skill contribution contains unknown attributes";
    assert lib.assertMsg (
      entry ? name && isSkillName entry.name
    ) "agent skill contribution has an invalid name";
    assert lib.assertMsg (
      entry ? definition && builtins.isAttrs entry.definition
    ) "agent skill contribution requires an attribute-set definition";
    assert lib.assertMsg (
      !entry ? enable || lib.isFunction entry.enable
    ) "agent skill contribution enable predicate must be a function";
    assert lib.assertMsg (
      entry ? provenance && lib.elem entry.provenance validProvenance
    ) "agent skill contribution has an invalid provenance";
    entry;
  enablePredicate =
    entry:
    if entry ? enable then
      config:
      let
        enabled = entry.enable config;
      in
      assert lib.assertMsg (builtins.isBool enabled)
        "agent skill contribution enable predicate must return a boolean";
      enabled
    else
      _: true;
  checked = map validateEntry entries;
  names = map (entry: entry.name) checked;
  duplicateNames = builtins.filter (
    name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1
  ) (lib.unique names);
in
assert lib.assertMsg (
  duplicateNames == [ ]
) "agent skills contain duplicate names: ${lib.concatStringsSep ", " duplicateNames}";
{
  definitions = builtins.listToAttrs (
    map (entry: lib.nameValuePair entry.name entry.definition) checked
  );
  provenance = builtins.listToAttrs (
    map (entry: lib.nameValuePair entry.name entry.provenance) checked
  );
  enablePredicates = builtins.listToAttrs (
    map (entry: lib.nameValuePair entry.name (enablePredicate entry)) checked
  );
}
