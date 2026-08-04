{ lib }:
{
  discoveredFiles,
  reservedNames ? [ ],
  shards,
}:
let
  shardNames = map (shard: shard.name) shards;
  duplicateShardNames = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) shardNames) > 1
  ) (lib.unique shardNames);
  reservedShardNames = lib.intersectLists shardNames reservedNames;
  declaredFiles = lib.concatMap (shard: shard.testFiles) shards;
  duplicateFiles = builtins.filter (
    file: builtins.length (builtins.filter (other: other == file) declaredFiles) > 1
  ) (lib.unique declaredFiles);
  staleDeclaredFiles = lib.subtractLists discoveredFiles declaredFiles;
  unassignedFiles = lib.subtractLists declaredFiles discoveredFiles;
in
if duplicateShardNames != [ ] then
  throw "duplicate Bats shard names: ${builtins.toJSON duplicateShardNames}"
else if reservedShardNames != [ ] then
  throw "Bats shard names collide with reserved check names: ${builtins.toJSON reservedShardNames}"
else if duplicateFiles != [ ] then
  throw "Bats files assigned to multiple shards: ${builtins.toJSON duplicateFiles}"
else if staleDeclaredFiles != [ ] then
  throw "Bats shard manifest references missing files: ${builtins.toJSON staleDeclaredFiles}"
else if unassignedFiles != [ ] then
  throw "Bats files are not assigned to a shard: ${builtins.toJSON unassignedFiles}"
else
  true
