{
  apps,
  validations,
}:
let
  appNames = builtins.attrNames apps;
  validationNames = builtins.attrNames validations;
in
if appNames != validationNames then
  throw "public app and validation names must match exactly: apps=${builtins.toJSON appNames}, validations=${builtins.toJSON validationNames}"
else
  {
    inherit appNames validationNames;
  }
