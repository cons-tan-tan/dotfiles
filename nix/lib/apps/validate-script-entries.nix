{ lib }:
entries:
let
  validEntry =
    entry:
    builtins.isAttrs entry
    && entry ? name
    && builtins.isString entry.name
    && entry.name != ""
    && entry ? mkDerivation
    && builtins.isFunction entry.mkDerivation;
in
if !builtins.isList entries then
  throw "app-scripts must be a list"
else if builtins.any (entry: !validEntry entry) entries then
  throw "app-scripts entries must contain a non-empty name and mkDerivation function"
else
  let
    names = map (entry: entry.name) entries;
    duplicateNames = builtins.filter (
      name: builtins.length (builtins.filter (other: other == name) names) > 1
    ) (lib.unique names);
  in
  if duplicateNames != [ ] then
    throw "app-scripts names must be unique: ${builtins.toJSON duplicateNames}"
  else
    entries
