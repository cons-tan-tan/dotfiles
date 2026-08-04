{ lib }:
let
  repoRoot = ../../../..;
  nixRoot = repoRoot + "/nix";
  modulesRoot = repoRoot + "/modules";
  discovery = import ../../../../nix/tests/test-discovery.nix { inherit lib; };
  isTestSource = path: lib.hasSuffix ".test.nix" (baseNameOf path);
  isFailureTest = path: lib.hasSuffix ".failure.test.nix" (baseNameOf path);
  isSupportPath =
    path: lib.hasInfix "/_tests/" (toString path) || lib.hasInfix "/_lib/" (toString path);
  candidateFiles =
    builtins.filter isTestSource (lib.filesystem.listFilesRecursive nixRoot)
    ++ builtins.filter (path: isSupportPath path && isTestSource path) (
      lib.filesystem.listFilesRecursive modulesRoot
    );
  expected = {
    testFiles = builtins.filter (path: !isFailureTest path) candidateFiles;
    failureTestFiles = builtins.filter isFailureTest candidateFiles;
  };
  repositoryDiscovery = discovery.discoverRepository {
    inherit modulesRoot nixRoot;
  };
  actual = discovery.classify repositoryDiscovery.files;
  sortPaths = paths: lib.sort builtins.lessThan (map toString paths);
in
{
  testDendriticPositiveTestsAreDiscovered = {
    expr = sortPaths actual.testFiles;
    expected = sortPaths expected.testFiles;
  };

  testDendriticFailureTestsAreDiscovered = {
    expr = sortPaths actual.failureTestFiles;
    expected = sortPaths expected.failureTestFiles;
  };

  testRepositoryDiscoveryKeepsBothSourceRoots = {
    expr = map (root: toString root.path) repositoryDiscovery.sourceRoots;
    expected = map toString [
      nixRoot
      modulesRoot
    ];
  };
}
