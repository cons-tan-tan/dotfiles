{ lib }:
entries:
let
  inherit (import ./skill-policy.nix { inherit lib; }) isSkillName;
  allowedEntryAttrs = [
    "definition"
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
    assert lib.assertMsg (builtins.isAttrs entry) "agent skill quirk entries must be attribute sets";
    assert lib.assertMsg (lib.all (name: lib.elem name allowedEntryAttrs) (
      builtins.attrNames entry
    )) "agent skill quirk entry contains unknown attributes";
    assert lib.assertMsg (
      entry ? name && isSkillName entry.name
    ) "agent skill quirk entry has an invalid name";
    assert lib.assertMsg (
      entry ? definition && builtins.isAttrs entry.definition
    ) "agent skill quirk entry requires an attribute-set definition";
    assert lib.assertMsg (
      entry ? provenance && lib.elem entry.provenance validProvenance
    ) "agent skill quirk entry has an invalid provenance";
    entry;
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
}
