{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  pkgs = import nixpkgsPath { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  mergeValidationProducers =
    import (repoRoot + "/modules/features/apps/_interface/validation-producers.nix")
      {
        inherit lib;
      };
  validateNames = import (repoRoot + "/modules/features/apps/_interface/validation-names.nix");
  force = value: builtins.deepSeq value true;
  merge = sets: force (mergeValidationProducers sets);
  validation = pkgs.writeText "fixture-validation" "validated";
  cases = {
    duplicateValidationNames = {
      expression = merge [
        { duplicate = validation; }
        { duplicate = validation; }
      ];
      expectedFragment = "app-validation names must be unique across producers";
    };
    publicAppWithoutValidation = {
      expression = force (validateNames {
        apps.orphan = { };
        validations = { };
      });
      expectedFragment = ''public app and validation names must match exactly: apps=["orphan"], validations=[]'';
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
