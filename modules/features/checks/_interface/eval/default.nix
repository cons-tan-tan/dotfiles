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
    {
      owner = "bootstrap eval suites";
      checks = bootstrap.buildChecks;
    }
    {
      owner = "failure eval suites";
      checks = harness.failureChecks inventory.failureTestFiles;
    }
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
