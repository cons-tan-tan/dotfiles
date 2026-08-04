# Public apps and their validation strategies are derived from the same record.
# Shell apps use their production script as the validation. Custom apps must
# provide an independent validation derivation explicitly.
{ lib }:
let
  normalizeEntry =
    name: entry:
    if !builtins.isAttrs entry then
      throw "app entry ${builtins.toJSON name} must be an attribute set"
    else if entry ? script then
      if
        builtins.attrNames entry != [
          "description"
          "script"
        ]
        || !builtins.isString entry.description
        || entry.description == ""
        || !lib.isDerivation entry.script
      then
        throw "shell app entry ${builtins.toJSON name} must contain a non-empty description and script derivation only"
      else
        {
          kind = "shell";
          app = {
            type = "app";
            meta.description = entry.description;
            program = lib.getExe entry.script;
          };
          validation = entry.script;
        }
    else if entry ? app then
      if
        builtins.attrNames entry != [
          "app"
          "validation"
        ]
        || !builtins.isAttrs entry.app
        || !(entry.app ? type)
        || !(entry.app ? program)
        || !(entry.app ? meta)
        || !lib.isDerivation entry.validation
      then
        throw "custom app entry ${builtins.toJSON name} must contain an app and exactly one validation derivation"
      else
        {
          kind = "custom";
          inherit (entry) app validation;
        }
    else
      throw "app entry ${builtins.toJSON name} must be either a shell app or a custom app with validation";

  exactNames =
    context: apps: validationsByName:
    let
      appNames = builtins.attrNames apps;
      validationNames = builtins.attrNames validationsByName;
    in
    if appNames == validationNames then
      true
    else
      throw "${context} app and validation names must match exactly: apps=${builtins.toJSON appNames}, validations=${builtins.toJSON validationNames}";

  duplicateNames =
    names:
    builtins.filter (name: builtins.length (builtins.filter (other: other == name) names) > 1) (
      lib.unique names
    );
in
{
  mkAppSet =
    args:
    if !builtins.isAttrs args || builtins.attrNames args != [ "entries" ] then
      throw "mkAppSet expects exactly an entries attribute"
    else if !builtins.isAttrs args.entries then
      throw "mkAppSet entries must be an attribute set"
    else
      let
        normalizedEntries = lib.mapAttrs normalizeEntry args.entries;
        # Force every entry discriminator without recursively forcing derivations.
        normalizedKinds = lib.mapAttrsToList (_: entry: entry.kind) normalizedEntries;
        apps = lib.mapAttrs (_: entry: entry.app) normalizedEntries;
        validationsByName = lib.mapAttrs (_: entry: entry.validation) normalizedEntries;
        exact = exactNames "app set" apps validationsByName;
      in
      builtins.deepSeq normalizedKinds (
        builtins.seq exact {
          inherit apps validationsByName;
          validations = builtins.attrValues validationsByName;
        }
      );

  mergeAppSets =
    appSets:
    let
      checkedAppSets = map (
        appSet:
        if !builtins.isAttrs appSet || !(appSet ? apps) || !(appSet ? validationsByName) then
          throw "merged app sets must contain apps and validationsByName"
        else
          builtins.seq (exactNames "merged input app set" appSet.apps appSet.validationsByName) appSet
      ) appSets;
      checkedTokens = map (appSet: builtins.attrNames appSet.apps) checkedAppSets;
      appNames = lib.concatMap (appSet: builtins.attrNames appSet.apps) checkedAppSets;
      validationNames = lib.concatMap (
        appSet: builtins.attrNames appSet.validationsByName
      ) checkedAppSets;
      duplicateAppNames = duplicateNames appNames;
      duplicateValidationNames = duplicateNames validationNames;
      apps = lib.foldl' (acc: appSet: acc // appSet.apps) { } checkedAppSets;
      validationsByName = lib.foldl' (acc: appSet: acc // appSet.validationsByName) { } checkedAppSets;
      exact = exactNames "merged app set" apps validationsByName;
    in
    builtins.deepSeq checkedTokens (
      if duplicateAppNames != [ ] || duplicateValidationNames != [ ] then
        throw "app and validation names must be unique across app sets: apps=${builtins.toJSON duplicateAppNames}, validations=${builtins.toJSON duplicateValidationNames}"
      else
        builtins.seq exact {
          inherit apps validationsByName;
          validations = builtins.attrValues validationsByName;
        }
    );
}
