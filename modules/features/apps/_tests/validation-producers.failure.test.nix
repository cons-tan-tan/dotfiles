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
  merge =
    producers:
    force (mergeValidationProducers {
      args = { };
      inherit producers;
    });
  validation = pkgs.writeText "fixture-validation" "validated";
  cases = {
    producerRecordWithoutProduce = {
      expression = merge [ { } ];
      expectedFragment = "app-validation producers must be { produce = <function>; } records";
    };

    nonFunctionProduceField = {
      expression = merge [ { produce = "not-a-function"; } ];
      expectedFragment = "app-validation producer records must contain produce functions";
    };

    nonAttributeSetProducerResult = {
      expression = merge [ { produce = _: [ ]; } ];
      expectedFragment = "app-validation producers must return attribute sets";
    };

    nonDerivationProducerValue = {
      expression = merge [ { produce = _: { invalid = "not-a-derivation"; }; } ];
      expectedFragment = "app-validation producers must return derivations";
    };

    duplicateValidationNames = {
      expression = merge [
        { produce = _: { duplicate = validation; }; }
        { produce = _: { duplicate = validation; }; }
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
