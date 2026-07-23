{
  pkgs,
  packageName,
  pinOverride,
  dependencyHashField,
  expectedDependencyProvenance,
  rawPin,
}:
let
  pin =
    rawPin
    // builtins.listToAttrs [
      {
        name = dependencyHashField;
        value = pkgs.lib.fakeHash;
      }
    ];
  package = builtins.getAttr packageName pkgs.dotfilesPackages;
  validatedPackage =
    if
      package ? updatePinsDependencyProvenance
      && package.updatePinsDependencyProvenance == expectedDependencyProvenance
    then
      package
    else
      builtins.throw "update-pins dependency provenance mismatch for ${packageName}";
in
validatedPackage.override (
  builtins.listToAttrs [
    {
      name = pinOverride;
      value = pin;
    }
  ]
)
