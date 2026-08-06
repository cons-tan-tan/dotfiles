{ lib }:
let
  ciCheck = import ../../ci/_interface/check.nix { inherit lib; };
  discovery = import ../_lib/test-discovery.nix { inherit lib; };
  bootstrap = import ../_data/bootstrap-paths.nix;
  inventory = import ../_interface/eval/inventory.nix {
    modulesRoot = ../../..;
    testDiscovery = discovery;
  };
  composeUniqueChecks = import ../_lib/compose.nix { inherit ciCheck lib; };
  validateBatsCatalog = import ../_lib/bats/validate-catalog.nix { inherit lib; };
  annotated = marker: {
    inherit marker;
    meta.dotfiles.hestia.targets = [ "fixture" ];
  };
  evaluationComplete = marker: {
    inherit marker;
    meta.dotfiles.ci.execution = "evaluation-complete";
  };
  classified = discovery.classify [
    "/repo/modules/feature-a/_tests/alpha.test.nix"
    "/repo/modules/feature-b/_tests/beta.test.nix"
    "/repo/modules/feature-b/_tests/gamma.failure.test.nix"
    "/repo/modules/feature-c/_tests/delta.suite.nix"
    "/repo/modules/feature-b/module.nix"
  ];
in
{
  testClassifiesTestsAcrossFeatureOwners = {
    expr = {
      tests = map discovery.checkName classified.testFiles;
      failures = map discovery.failureCheckName classified.failureTestFiles;
      suites = map toString classified.denSuiteFiles;
    };
    expected = {
      tests = [
        "alpha-tests"
        "beta-tests"
      ];
      failures = [ "gamma-failure-tests" ];
      suites = [ "/repo/modules/feature-c/_tests/delta.suite.nix" ];
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

  testEvaluationInventoryContainsOnlyAutoPositiveSuites = {
    expr = {
      autoPositive = builtins.elem "ci-check-tests" (map discovery.checkName inventory.testFiles);
      bootstrapPositive = builtins.any (
        path: builtins.elem path inventory.testFiles
      ) bootstrap.evaluationComplete;
      failureSuite = builtins.elem "home-contract-protocol.failure.test.nix" (
        map baseNameOf inventory.testFiles
      );
      denSuite = builtins.elem "den-schema.suite.nix" (map baseNameOf inventory.testFiles);
      sourcesExist = builtins.all builtins.pathExists bootstrap.all;
    };
    expected = {
      autoPositive = true;
      bootstrapPositive = false;
      failureSuite = false;
      denSuite = false;
      sourcesExist = true;
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

  testEvaluationCompleteCheckOwnerComposes = {
    expr = composeUniqueChecks {
      producers = [
        {
          owner = "evaluated";
          checks.evaluated = evaluationComplete 1;
        }
      ];
    };
    expected.evaluated = evaluationComplete 1;
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

}
