{ lib }:
let
  featuresRoot = ../..;
  protocolPath = ../_data/registry-protocol.json;
  protocol = builtins.fromJSON (builtins.readFile protocolPath);
  manifestFiles = builtins.filter (
    path: baseNameOf path == "update-pin.json" && baseNameOf (dirOf path) == "_interface"
  ) (lib.filesystem.listFilesRecursive featuresRoot);
  load = path: {
    source = path;
    value = builtins.fromJSON (builtins.readFile path);
  };
  declarations = map load manifestFiles;
  entries = map (declaration: declaration.value) declarations;
  expectedFields = [
    "kind"
    "name"
  ];
  malformed = builtins.filter (
    declaration:
    !builtins.isAttrs declaration.value
    || builtins.attrNames declaration.value != expectedFields
    || !builtins.isString declaration.value.name
    || !builtins.isAttrs declaration.value.kind
    || !builtins.isString (declaration.value.kind.type or null)
  ) declarations;
  duplicatesFor =
    field:
    builtins.filter (
      value: builtins.length (builtins.filter (entry: entry.${field} == value) entries) > 1
    ) (lib.unique (map (entry: entry.${field}) entries));
  duplicateNames = duplicatesFor "name";
  protocolTargetsValid = builtins.all (
    target:
    builtins.isAttrs target
    &&
      builtins.attrNames target == [
        "name"
        "target"
      ]
    && builtins.isString target.name
    && builtins.isString target.target
  ) protocol.targetOrder;
  protocolTargetNames = map (target: target.name) protocol.targetOrder;
  protocolTargetValues = map (target: target.target) protocol.targetOrder;
  duplicateProtocolNames = builtins.filter (
    name: builtins.length (builtins.filter (candidate: candidate == name) protocolTargetNames) > 1
  ) (lib.unique protocolTargetNames);
  duplicateProtocolTargets = builtins.filter (
    target: builtins.length (builtins.filter (candidate: candidate == target) protocolTargetValues) > 1
  ) (lib.unique protocolTargetValues);
  entriesForName = name: builtins.filter (entry: entry.name == name) entries;
  orderedEntries = map (
    target:
    builtins.head (entriesForName target.name)
    // {
      inherit (target) target;
    }
  ) protocol.targetOrder;
  sourceAuthorityFor =
    entry:
    if entry.kind.type == "paired-release" then
      entry.kind.source.authority
    else if entry.kind.type == "published-node-package" then
      entry.kind.dependencies.source.authority
    else
      null;
  managedPathsFor =
    entry:
    let
      authority = sourceAuthorityFor entry;
      sharedFlakePaths = [
        protocol.flakeFile.generatedPath
        protocol.flakeFile.lockPath
      ];
    in
    if authority != null then
      [
        entry.kind.pin
        authority.sourcePath
      ]
      ++ sharedFlakePaths
    else if entry.kind.type == "shellfirm" then
      [
        entry.kind.pin
        entry.kind.lock
        entry.kind.guardManifest
        entry.kind.guardLock
      ]
    else
      [ entry.kind.pin ];
  entriesWithManagedPaths = map (
    entry: entry // { managedPaths = managedPathsFor entry; }
  ) orderedEntries;
  allManagedPaths = lib.concatMap (entry: entry.managedPaths) entriesWithManagedPaths;
  sourceFiles = lib.unique allManagedPaths;
  unsafePaths = builtins.filter (
    path:
    path == ""
    || lib.hasPrefix "/" path
    || builtins.any (
      component:
      builtins.elem component [
        ""
        "."
        ".."
      ]
    ) (lib.splitString "/" path)
  ) sourceFiles;
  sharedManagedPaths = [
    protocol.flakeFile.generatedPath
    protocol.flakeFile.lockPath
  ];
  conflictingManagedPaths = builtins.filter (
    path:
    !(builtins.elem path sharedManagedPaths)
    && builtins.length (builtins.filter (candidate: candidate == path) allManagedPaths) > 1
  ) sourceFiles;
  targetNames = map (entry: entry.name) entries;
  targetOrderMismatch =
    lib.sort builtins.lessThan targetNames != lib.sort builtins.lessThan protocolTargetNames;
  validation =
    if
      builtins.attrNames protocol != [
        "flakeFile"
        "schemaVersion"
        "targetOrder"
      ]
      || protocol.schemaVersion != 1
      || !builtins.isList protocol.targetOrder
      || !protocolTargetsValid
    then
      throw "Invalid update-pin registry protocol"
    else if manifestFiles == [ ] then
      throw "No Feature-owned update-pin manifests were discovered"
    else if malformed != [ ] then
      throw "Malformed update-pin manifests: ${
        builtins.toJSON (map (entry: toString entry.source) malformed)
      }"
    else if
      duplicateNames != [ ] || duplicateProtocolNames != [ ] || duplicateProtocolTargets != [ ]
    then
      throw "Duplicate update-pin identity: ${
        builtins.toJSON {
          names = duplicateNames;
          protocolNames = duplicateProtocolNames;
          protocolTargets = duplicateProtocolTargets;
        }
      }"
    else if targetOrderMismatch then
      throw "Update-pin target order does not match owner manifests: ${
        builtins.toJSON {
          declared = lib.sort builtins.lessThan targetNames;
          expected = lib.sort builtins.lessThan protocolTargetNames;
        }
      }"
    else if unsafePaths != [ ] then
      throw "Unsafe update-pin managed paths: ${builtins.toJSON unsafePaths}"
    else if conflictingManagedPaths != [ ] then
      throw "Conflicting update-pin managed paths: ${builtins.toJSON conflictingManagedPaths}"
    else
      null;
in
builtins.seq validation {
  entries = entriesWithManagedPaths;
  manifestSource = lib.fileset.toSource {
    root = featuresRoot;
    fileset = lib.fileset.unions ([ protocolPath ] ++ manifestFiles);
  };
}
