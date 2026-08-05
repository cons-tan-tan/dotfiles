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
  repositoryDiscovery = testDiscovery.discoverRepository {
    inherit modulesRoot;
  };
  classifiedTests = testDiscovery.classify repositoryDiscovery.files;
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
  testFiles = testDiscovery.excludePaths bootstrap.paths classifiedTests.testFiles;
in
{
  producers = [
    {
      owner = "bootstrap eval suites";
      inherit (bootstrap) checks;
    }
    {
      owner = "auto eval suites";
      checks = harness.positiveChecks testFiles;
    }
    {
      owner = "failure eval suites";
      checks = harness.failureChecks classifiedTests.failureTestFiles;
    }
  ];
}
