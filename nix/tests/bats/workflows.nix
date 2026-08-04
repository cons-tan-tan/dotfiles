{ lib }:
let
  fromEntries =
    entries:
    let
      names = lib.sort builtins.lessThan (
        builtins.filter (
          name: entries.${name} == "regular" && (lib.hasSuffix ".yml" name || lib.hasSuffix ".yaml" name)
        ) (builtins.attrNames entries)
      );
    in
    if names == [ ] then
      throw "workflow discovery found no .yml or .yaml files"
    else
      map (name: ".github/workflows/${name}") names;
in
{
  inherit fromEntries;
  discover = workflowsRoot: fromEntries (builtins.readDir workflowsRoot);
}
