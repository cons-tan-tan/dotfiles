{ lib }:
names:
let
  validName =
    name:
    builtins.isString name && name != "" && builtins.match "^[A-Za-z0-9][A-Za-z0-9+._-]*$" name != null;
in
if !builtins.isList names then
  throw "flake-unfree-packages must be a list"
else if builtins.any (name: !validName name) names then
  throw "flake-unfree-packages entries must be non-empty package names"
else
  lib.unique names
