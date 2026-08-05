{ lib }:
let
  registry = import ../_lib/registry.nix { inherit lib; };
  entries = registry.entries;
  sourceAuthorityFor =
    entry:
    if entry.kind.type == "paired-release" then
      entry.kind.source.authority
    else if entry.kind.type == "published-node-package" then
      entry.kind.dependencies.source.authority
    else
      null;
in
{
  sourceFiles = lib.unique (lib.concatMap (entry: entry.managedPaths) entries);

  fixture = {
    managedPinPaths = map (entry: entry.kind.pin) entries;
    pairedInputFiles = builtins.filter (path: path != null) (
      map (
        entry:
        let
          authority = sourceAuthorityFor entry;
        in
        if authority == null then null else authority.sourcePath
      ) entries
    );
    pairedSources = builtins.filter (source: source != null) (
      map (
        entry:
        let
          authority = sourceAuthorityFor entry;
          source =
            if entry.kind.type == "paired-release" then
              entry.kind.source
            else if entry.kind.type == "published-node-package" then
              entry.kind.dependencies.source
            else
              null;
        in
        if authority == null then
          null
        else
          {
            inherit (source) input repository;
            inherit (authority) sourcePath;
          }
      ) entries
    );
    shellfirmCompanionPaths = lib.concatMap (
      entry:
      lib.optionals (entry.kind.type == "shellfirm") [
        entry.kind.lock
        entry.kind.guardManifest
        entry.kind.guardLock
      ]
    ) entries;
  };
}
