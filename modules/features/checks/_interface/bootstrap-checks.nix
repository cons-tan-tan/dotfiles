{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
  testContext,
  testDiscovery,
}:
let
  bootstrap = import ../_data/bootstrap-paths.nix;
  paths = bootstrap.all;

  harness = import ../_lib/eval/harness.nix {
    inherit
      ciCheck
      lib
      pkgs
      repoRoot
      testContext
      testDiscovery
      ;
  };
  positiveValues = harness.positiveValues paths;
  discoveryCheckName = testDiscovery.checkName bootstrap.discovery;
  diagnosticContract = harness.isolatedFailureCheck {
    name = "test-discovery-diagnostics";
    path = ../_tests/fixtures/test-discovery-diagnostics.failure.fixture.nix;
  };
  buildEntries.${discoveryCheckName} = ciCheck.buildEntry (ciCheck.targets.both "eval-tests") (
    pkgs.linkFarm discoveryCheckName [
      {
        name = "positive";
        path = positiveValues.${discoveryCheckName};
      }
      {
        name = "diagnostics";
        path = diagnosticContract;
      }
    ]
  );
  evaluationCompleteChecks = removeAttrs positiveValues [ discoveryCheckName ];
in
{
  inherit paths;
  names = map testDiscovery.checkName paths;
  inherit buildEntries evaluationCompleteChecks;
}
