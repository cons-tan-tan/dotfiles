{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  aggregate = import (repoRoot + "/modules/features/agents/skills/_lib/aggregate.nix") {
    inherit lib;
  };
  force = value: builtins.deepSeq value true;
  valid = {
    name = "demo";
    definition.root = ./.;
    provenance = "local";
  };
  cases = {
    duplicateSkillNames = {
      expression = force (aggregate [
        valid
        valid
      ]);
      expectedFragment = "agent skills contain duplicate names: demo";
    };
    invalidSkillProvenance = {
      expression = force (aggregate [ (valid // { provenance = "unknown"; }) ]);
      expectedFragment = "agent skill quirk entry has an invalid provenance";
    };
    invalidSkillEnablePredicate = {
      expression = force (aggregate [ (valid // { enable = true; }) ]);
      expectedFragment = "agent skill quirk entry enable predicate must be a function";
    };
    nonBooleanSkillEnablePredicate = {
      expression = (aggregate [ (valid // { enable = _: "yes"; }) ]).enablePredicates.demo { };
      expectedFragment = "agent skill quirk entry enable predicate must return a boolean";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
