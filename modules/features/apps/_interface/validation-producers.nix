{ lib }:
sets:
let
  names = lib.concatMap builtins.attrNames sets;
  duplicates = lib.filter (name: builtins.length (lib.filter (other: other == name) names) > 1) (
    lib.unique names
  );
in
assert lib.assertMsg (
  duplicates == [ ]
) "app-validation names must be unique across producers: ${builtins.toJSON duplicates}";
lib.foldl' (acc: validations: acc // validations) { } sets
