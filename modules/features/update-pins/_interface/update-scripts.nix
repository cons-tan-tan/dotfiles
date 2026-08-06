{ pkgs }:
let
  inherit (pkgs) lib;

  normalizeCommand =
    name: value:
    let
      command = if builtins.isAttrs value && value ? command then value.command else value;
    in
    if builtins.isString command then
      [ command ]
    else if builtins.isList command && builtins.all builtins.isString command && command != [ ] then
      command
    else
      throw "update script ${builtins.toJSON name} must be a command string or a non-empty argv list";

  collect =
    path: value:
    if builtins.isAttrs value && value ? updateScriptName then
      let
        name = value.updateScriptName;
      in
      if !(value ? updateScript) then
        throw "update script ${builtins.toJSON name} is missing updateScript"
      else if !builtins.isString name || name == "" then
        throw "updateScriptName at ${builtins.toJSON path} must be a non-empty string"
      else
        [
          {
            inherit name;
            value = {
              command = normalizeCommand name value.updateScript;
              description = value.updateScriptDescription or "Update ${name}";
            };
          }
        ]
    else if lib.isDerivation value || !builtins.isAttrs value then
      [ ]
    else
      lib.concatMap (name: collect (path ++ [ name ]) value.${name}) (builtins.attrNames value);

  entries =
    collect [ "dotfilesPackages" ] pkgs.dotfilesPackages ++ collect [ "watchexec" ] pkgs.watchexec;
  names = map (entry: entry.name) entries;
  duplicates = builtins.filter (
    name: builtins.length (builtins.filter (other: other == name) names) > 1
  ) (lib.unique names);
in
if duplicates != [ ] then
  throw "duplicate package update script names: ${builtins.toJSON duplicates}"
else
  builtins.listToAttrs entries
