{ lib, repoRoot }:
let
  harness = import ../_lib/eval/den-suite-harness.nix {
    ciCheck = { };
    inputs = { };
    inherit lib repoRoot;
    pkgs = { };
  };
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
in
{
  testAcceptsSelfDescribingSuite = {
    expr = harness.validateFixture "/repo/modules/feature/_tests/fixture.suite.nix" fixture;
    expected = null;
  };

  testAcceptsSuiteWithoutFailureCases = {
    expr = harness.validateFixture "/repo/modules/feature/_tests/fixture.suite.nix" (
      fixture // { failureCases = { }; }
    );
    expected = null;
  };

  testAcceptsEvaluationCompleteSuiteWithoutFailureCases = {
    expr = harness.validateFixture "/repo/modules/feature/_tests/fixture.suite.nix" (
      fixture
      // {
        meta = fixture.meta // {
          execution = "evaluation-complete";
          hestiaGroup = null;
        };
        failureCases = { };
      }
    );
    expected = null;
  };

  testAcceptsUniqueSuiteIdentities = {
    expr = harness.validateSuiteIdentities [
      {
        path = "/repo/modules/feature-a/_tests/dataflow.suite.nix";
        inherit fixture;
      }
      {
        path = "/repo/modules/feature-b/_tests/dataflow.suite.nix";
        fixture = fixture // {
          meta = fixture.meta // {
            checkName = "second-den-suite-tests";
          };
        };
      }
    ];
    expected = null;
  };
}
