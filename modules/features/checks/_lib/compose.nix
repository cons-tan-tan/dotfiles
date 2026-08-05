{ ciCheck, lib }:
{
  producers,
  reservedCheckNames ? [ ],
}:
let
  producerEntries = lib.concatMap (
    producer:
    map (name: {
      inherit name;
      inherit (producer) owner;
    }) (builtins.attrNames producer.checks)
  ) producers;
  reservedEntries = map (name: {
    inherit name;
    owner = "reserved";
  }) reservedCheckNames;
  entries = producerEntries ++ reservedEntries;
  names = map (entry: entry.name) entries;
  duplicateNames = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) names) > 1
  ) (lib.unique names);
  collisions = map (name: {
    inherit name;
    owners = map (entry: entry.owner) (builtins.filter (entry: entry.name == name) entries);
  }) duplicateNames;
  validateProducer =
    producer:
    builtins.mapAttrs (
      name: check:
      if ciCheck.isClassified check then
        check
      else
        throw "check missing a unique CI execution classification: ${
          builtins.toJSON {
            inherit name;
            inherit (producer) owner;
          }
        }"
    ) producer.checks;
in
if collisions != [ ] then
  throw "check owner collisions: ${builtins.toJSON collisions}"
else
  # 各checkの分類は、そのcheckが選択された時に検証する。ここで全値を
  # 強制すると、flake.checksを参照するeval suiteとのfixed pointを壊す。
  builtins.foldl' (checks: producer: checks // validateProducer producer) { } producers
