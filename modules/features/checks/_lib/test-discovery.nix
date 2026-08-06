{ lib }:
let
  testSuffix = ".test.nix";
  failureTestSuffix = ".failure.test.nix";
  denSuiteSuffix = ".suite.nix";

  testStem = path: lib.removeSuffix testSuffix (baseNameOf path);
  failureStem = path: lib.removeSuffix failureTestSuffix (baseNameOf path);
  selectSourceRootFiles = sourceRoot: files: builtins.filter sourceRoot.include files;
  repositorySourceRoots =
    { modulesRoot }:
    [
      {
        path = modulesRoot;
        include = path: lib.hasInfix "/_tests/" (toString path);
      }
    ];
in
{
  inherit repositorySourceRoots selectSourceRootFiles;

  discover =
    sourceRoots:
    lib.concatMap (
      sourceRoot: selectSourceRootFiles sourceRoot (lib.filesystem.listFilesRecursive sourceRoot.path)
    ) sourceRoots;

  discoverRepository =
    roots:
    let
      sourceRoots = repositorySourceRoots roots;
    in
    {
      inherit sourceRoots;
      files = lib.concatMap (
        sourceRoot: selectSourceRootFiles sourceRoot (lib.filesystem.listFilesRecursive sourceRoot.path)
      ) sourceRoots;
    };

  excludePaths =
    excludedPaths: files:
    let
      excluded = map toString excludedPaths;
    in
    builtins.filter (path: !builtins.elem (toString path) excluded) files;

  classify =
    files:
    let
      failureTestFiles = builtins.filter (path: lib.hasSuffix failureTestSuffix (baseNameOf path)) files;
      denSuiteFiles = builtins.filter (path: lib.hasSuffix denSuiteSuffix (baseNameOf path)) files;
      testFiles = builtins.filter (
        path:
        lib.hasSuffix testSuffix (baseNameOf path) && !lib.hasSuffix failureTestSuffix (baseNameOf path)
      ) files;
    in
    {
      inherit denSuiteFiles failureTestFiles testFiles;
    };

  checkName = path: "${testStem path}-tests";
  failureCheckName = path: "${failureStem path}-failure-tests";

  duplicateNames =
    names:
    builtins.filter (name: builtins.length (builtins.filter (other: other == name) names) > 1) (
      lib.unique names
    );

  collidingNames = left: right: lib.intersectLists (lib.unique left) (lib.unique right);
}
