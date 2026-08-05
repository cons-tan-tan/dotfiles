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
  harness = import ./harness.nix {
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
  producers = [
    {
      owner = "bootstrap eval suites";
      inherit (bootstrap) checks;
    }
    {
      owner = "auto eval suites";
      checks = harness.positiveChecks inventory.testFiles;
    }
    {
      owner = "failure eval suites";
      checks = harness.failureChecks inventory.failureTestFiles;
    }
  ];
}
