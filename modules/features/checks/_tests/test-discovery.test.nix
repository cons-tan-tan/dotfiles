{ lib }:
let
  discovery = import ../_lib/test-discovery.nix { inherit lib; };
  composeUniqueChecks = import ../_lib/compose.nix { inherit lib; };
  validateBatsCatalog = import ../_lib/bats/validate-catalog.nix { inherit lib; };
  annotated = marker: {
    inherit marker;
    meta.dotfiles.hestia.targets = [ "fixture" ];
  };
  classified = discovery.classify [
    "/repo/modules/feature-a/_tests/alpha.test.nix"
    "/repo/modules/feature-b/_tests/beta.test.nix"
    "/repo/modules/feature-b/_tests/gamma.failure.test.nix"
    "/repo/modules/feature-b/module.nix"
  ];
in
{
  testClassifiesTestsAcrossFeatureOwners = {
    expr = {
      tests = map discovery.checkName classified.testFiles;
      failures = map discovery.failureCheckName classified.failureTestFiles;
    };
    expected = {
      tests = [
        "alpha-tests"
        "beta-tests"
      ];
      failures = [ "gamma-failure-tests" ];
    };
  };

  testSourceRootSelectionAppliesIncludePredicate = {
    expr =
      discovery.selectSourceRootFiles
        {
          include = path: lib.hasInfix "/_tests/" path;
        }
        [
          "/repo/modules/feature/_tests/alpha.test.nix"
          "/repo/modules/feature/alpha.nix"
        ];
    expected = [ "/repo/modules/feature/_tests/alpha.test.nix" ];
  };

  testFailureTestsAreNotAlsoPositiveTests = {
    expr = {
      positive = classified.testFiles;
      failure = classified.failureTestFiles;
    };
    expected = {
      positive = [
        "/repo/modules/feature-a/_tests/alpha.test.nix"
        "/repo/modules/feature-b/_tests/beta.test.nix"
      ];
      failure = [ "/repo/modules/feature-b/_tests/gamma.failure.test.nix" ];
    };
  };

  testBootstrapExclusionUsesCanonicalPath = {
    expr =
      discovery.excludePaths
        [ "/repo/modules/checks/_tests/shared.test.nix" ]
        [
          "/repo/modules/checks/_tests/shared.test.nix"
          "/repo/modules/feature/_tests/shared.test.nix"
        ];
    expected = [ "/repo/modules/feature/_tests/shared.test.nix" ];
  };

  testRejectsDuplicateBasenamesAcrossFeatureOwners = {
    expr = discovery.duplicateNames [
      (discovery.checkName "/repo/modules/checks/_tests/shared.test.nix")
      (discovery.checkName "/repo/modules/feature/_tests/shared.test.nix")
    ];
    expected = [ "shared-tests" ];
  };

  testFindsCheckClusterCollisionsBeforeMerge = {
    expr =
      discovery.collidingNames
        [
          "package-smoke-tests"
          "reuse-lint"
        ]
        [
          "reuse-lint"
          "safe-fetch-e2e"
        ];
    expected = [ "reuse-lint" ];
  };

  testUniqueCheckOwnersCompose = {
    expr = composeUniqueChecks {
      producers = [
        {
          owner = "alpha";
          checks.alpha = annotated 1;
        }
        {
          owner = "beta";
          checks.beta = annotated 2;
        }
      ];
    };
    expected = {
      alpha = annotated 1;
      beta = annotated 2;
    };
  };

  testCheckOwnerCollisionIsRejected = {
    expr =
      (builtins.tryEval (composeUniqueChecks {
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
      })).success;
    expected = false;
  };

  testReservedCheckCollisionIsRejected = {
    expr =
      (builtins.tryEval (composeUniqueChecks {
        producers = [
          {
            owner = "alpha";
            checks.shared = annotated 1;
          }
        ];
        reservedCheckNames = [ "shared" ];
      })).success;
    expected = false;
  };

  testMissingHestiaMetadataIsRejected = {
    expr =
      (builtins.tryEval
        (composeUniqueChecks {
          producers = [
            {
              owner = "alpha";
              checks.unannotated = {
                marker = 1;
              };
            }
          ];
        }).unannotated
      ).success;
    expected = false;
  };

  testBatsCatalogAcceptsExactAssignment = {
    expr = validateBatsCatalog {
      discoveredFiles = [ "bats/a.bats" ];
      shards = [
        {
          name = "fixture";
          testFiles = [ "bats/a.bats" ];
        }
      ];
    };
    expected = true;
  };

  testBatsCatalogRejectsDuplicateFile = {
    expr =
      (builtins.tryEval (validateBatsCatalog {
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
      })).success;
    expected = false;
  };

  testBatsCatalogRejectsUnassignedDiscoveredFile = {
    expr =
      (builtins.tryEval (validateBatsCatalog {
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
      })).success;
    expected = false;
  };

  testBatsCatalogRejectsStaleDeclaredFile = {
    expr =
      (builtins.tryEval (validateBatsCatalog {
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
      })).success;
    expected = false;
  };

  testBatsCatalogRejectsDuplicateShardName = {
    expr =
      (builtins.tryEval (validateBatsCatalog {
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
      })).success;
    expected = false;
  };

  testBatsCatalogRejectsReservedAggregateName = {
    expr =
      (builtins.tryEval (validateBatsCatalog {
        discoveredFiles = [ "bats/a.bats" ];
        reservedNames = [ "bats-tests" ];
        shards = [
          {
            name = "bats-tests";
            testFiles = [ "bats/a.bats" ];
          }
        ];
      })).success;
    expected = false;
  };
}
