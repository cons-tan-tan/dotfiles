{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  ciCheck = import (repoRoot + "/modules/features/ci/_interface/check.nix") { inherit lib; };
  checksLib = repoRoot + "/modules/features/checks/_lib";
  testDiscovery = import (checksLib + "/test-discovery.nix") { inherit lib; };
  composeUniqueChecks = import (checksLib + "/compose.nix") { inherit ciCheck lib; };
  validateBatsCatalog = import (checksLib + "/bats/validate-catalog.nix") { inherit lib; };
  harness = import (checksLib + "/eval/harness.nix") {
    inherit
      ciCheck
      lib
      repoRoot
      testDiscovery
      ;
    # These cases fail during name/metadata validation before a derivation is made.
    pkgs = { };
    testContext = { };
  };
  annotated = marker: {
    inherit marker;
    meta.dotfiles.hestia.targets = [ "fixture" ];
  };
  force = value: builtins.deepSeq value true;
  cases = {
    duplicatePositiveEvalChecks = {
      expression = force (
        harness.positiveChecks [
          "/fixture/first/shared.test.nix"
          "/fixture/second/shared.test.nix"
        ]
      );
      expectedFragment = ''positive eval suites produces duplicate check names: ["shared-tests"]'';
    };

    duplicateFailureEvalChecks = {
      expression = force (
        harness.failureChecks [
          "/fixture/first/shared.failure.test.nix"
          "/fixture/second/shared.failure.test.nix"
        ]
      );
      expectedFragment = ''failure eval suites produces duplicate check names: ["shared-failure-tests"]'';
    };

    checkOwnerCollision = {
      expression = force (composeUniqueChecks {
        producers = [
          {
            owner = "alpha";
            checks.shared = annotated 1;
          }
          {
            owner = "beta";
            checks.shared = annotated 2;
          }
        ];
      });
      expectedFragment = ''"owners":["alpha","beta"]'';
    };

    reservedCheckCollision = {
      expression = force (composeUniqueChecks {
        producers = [
          {
            owner = "alpha";
            checks.shared = annotated 1;
          }
        ];
        reservedCheckNames = [ "shared" ];
      });
      expectedFragment = ''"owners":["alpha","reserved"]'';
    };

    missingHestiaMetadata = {
      expression = force (composeUniqueChecks {
        producers = [
          {
            owner = "alpha";
            checks.unannotated = {
              marker = 1;
            };
          }
        ];
      });
      expectedFragment = ''{"name":"unannotated","owner":"alpha"}'';
    };

    unknownExecutionClassification = {
      expression = force (
        (composeUniqueChecks {
          producers = [
            {
              owner = "alpha";
              checks.unknown.meta.dotfiles.ci.execution = "sometimes-build";
            }
          ];
        }).unknown
      );
      expectedFragment = ''{"name":"unknown","owner":"alpha"}'';
    };

    duplicateBatsFile = {
      expression = force (validateBatsCatalog {
        discoveredFiles = [ "bats/a.bats" ];
        shards = [
          {
            name = "first";
            testFiles = [ "bats/a.bats" ];
          }
          {
            name = "second";
            testFiles = [ "bats/a.bats" ];
          }
        ];
      });
      expectedFragment = ''Bats files assigned to multiple shards: ["bats/a.bats"]'';
    };

    duplicateBatsShardName = {
      expression = force (validateBatsCatalog {
        discoveredFiles = [
          "bats/a.bats"
          "bats/b.bats"
        ];
        shards = [
          {
            name = "fixture";
            testFiles = [ "bats/a.bats" ];
          }
          {
            name = "fixture";
            testFiles = [ "bats/b.bats" ];
          }
        ];
      });
      expectedFragment = ''duplicate Bats shard names: ["fixture"]'';
    };

    staleBatsCatalogEntry = {
      expression = force (validateBatsCatalog {
        discoveredFiles = [ "bats/a.bats" ];
        shards = [
          {
            name = "fixture";
            testFiles = [
              "bats/a.bats"
              "bats/missing.bats"
            ];
          }
        ];
      });
      expectedFragment = ''Bats shard manifest references missing files: ["bats/missing.bats"]'';
    };

    unassignedBatsFile = {
      expression = force (validateBatsCatalog {
        discoveredFiles = [
          "bats/a.bats"
          "bats/b.bats"
        ];
        shards = [
          {
            name = "fixture";
            testFiles = [ "bats/a.bats" ];
          }
        ];
      });
      expectedFragment = ''Bats files are not assigned to a shard: ["bats/b.bats"]'';
    };

    reservedBatsShardName = {
      expression = force (validateBatsCatalog {
        discoveredFiles = [ "bats/a.bats" ];
        reservedNames = [ "bats-tests" ];
        shards = [
          {
            name = "bats-tests";
            testFiles = [ "bats/a.bats" ];
          }
        ];
      });
      expectedFragment = ''Bats shard names collide with reserved check names: ["bats-tests"]'';
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
