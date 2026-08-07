{
  ciCheck,
  lib,
  modulesRoot,
  pkgs,
  repoRoot,
  testContext,
  testDiscovery,
}:
let
  inventory = import ./inventory.nix {
    inherit modulesRoot testDiscovery;
  };
  bootstrap = import ../bootstrap-checks.nix {
    inherit
      ciCheck
      lib
      pkgs
      repoRoot
      testContext
      testDiscovery
      ;
  };
  harness = import ../../_lib/eval/harness.nix {
    inherit
      ciCheck
      lib
      pkgs
      repoRoot
      testContext
      testDiscovery
      ;
  };
in
{
  buildProducers = [
    (ciCheck.mkBuildProducer {
      owner = "bootstrap eval suites";
      entries = bootstrap.buildEntries;
    })
    (ciCheck.mkBuildProducer {
      owner = "failure eval suites";
      entries = harness.failureEntries inventory.failureTestFiles;
    })
  ];
  evaluationCompleteProducers = [
    {
      owner = "bootstrap eval suites";
      checks = bootstrap.evaluationCompleteChecks;
    }
    {
      owner = "auto eval suites";
      checks = harness.positiveValues inventory.testFiles;
    }
  ];
}
