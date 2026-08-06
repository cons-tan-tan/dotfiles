{
  modulesRoot,
  testDiscovery,
}:
let
  bootstrap = import ../../_data/bootstrap-paths.nix;
  repositoryDiscovery = testDiscovery.discoverRepository {
    inherit modulesRoot;
  };
  classifiedTests = testDiscovery.classify repositoryDiscovery.files;
  testFiles = testDiscovery.excludePaths bootstrap.all classifiedTests.testFiles;
in
{
  inherit testFiles;
  inherit (classifiedTests) denSuiteFiles;
  inherit (classifiedTests) failureTestFiles;
}
