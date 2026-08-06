{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  harness = import (repoRoot + "/modules/features/checks/_lib/eval/den-suite-harness.nix") {
    ciCheck = { };
    inputs = { };
    inherit lib repoRoot;
    pkgs = { };
  };
  path = "/repo/modules/feature/_tests/fixture.suite.nix";
  fixture = {
    meta = {
      checkName = "fixture-den-suite-tests";
      execution = "build";
      hestiaGroup = "eval-tests";
    };
    tests.testExample = {
      expr = 1;
      expected = 1;
    };
    failureCases.exampleFailure = {
      expression = throw "fixture failure";
      expectedFragments = [ "fixture failure" ];
    };
  };
  force = value: builtins.deepSeq value true;
  cases = {
    unknownRootField = {
      expression = harness.validateFixture path (fixture // { unexpected = true; });
      expectedFragment = "must contain exactly failureCases, meta, and tests";
    };
    invalidMetadata = {
      expression = harness.validateFixture path (fixture // { meta.checkName = "invalid_check_name"; });
      expectedFragment = "has invalid Den suite metadata";
    };
    emptyPositiveTests = {
      expression = harness.validateFixture path (fixture // { tests = { }; });
      expectedFragment = "must define at least one positive test";
    };
    malformedPositiveTest = {
      expression = harness.validateFixture path (
        fixture
        // {
          tests.testExample = {
            expr = true;
          };
        }
      );
      expectedFragment = "contains invalid positive tests";
    };
    unknownPositiveTestField = {
      expression = harness.validateFixture path (
        fixture
        // {
          tests.testExample = fixture.tests.testExample // {
            unexpected = true;
          };
        }
      );
      expectedFragment = "contains invalid positive tests";
    };
    emptyExpectedFragments = {
      expression = harness.validateFixture path (
        fixture // { failureCases.exampleFailure.expectedFragments = [ ]; }
      );
      expectedFragment = "contains invalid failure cases";
    };
    blankExpectedFragment = {
      expression = harness.validateFixture path (
        fixture // { failureCases.exampleFailure.expectedFragments = [ "  " ]; }
      );
      expectedFragment = "contains invalid failure cases";
    };
    unknownFailureCaseField = {
      expression = harness.validateFixture path (
        fixture
        // {
          failureCases.exampleFailure = fixture.failureCases.exampleFailure // {
            unexpected = true;
          };
        }
      );
      expectedFragment = "contains invalid failure cases";
    };
    evaluationCompleteFailureCase = {
      expression = harness.validateFixture path (
        fixture
        // {
          meta = fixture.meta // {
            execution = "evaluation-complete";
            hestiaGroup = null;
          };
        }
      );
      expectedFragment = "evaluation-complete suites cannot define failure cases";
    };
    duplicateSuitePath = {
      expression = force (
        harness.validateSuiteIdentities [
          {
            inherit fixture path;
          }
          {
            inherit fixture path;
          }
        ]
      );
      expectedFragment = "Den suite paths must be unique";
    };
    duplicateSuiteCheckName = {
      expression = force (
        harness.validateSuiteIdentities [
          {
            inherit fixture;
            path = "/repo/modules/feature-a/_tests/fixture.suite.nix";
          }
          {
            inherit fixture;
            path = "/repo/modules/feature-b/_tests/fixture.suite.nix";
          }
        ]
      );
      expectedFragment = "Den suite check names must be unique";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
