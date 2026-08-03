{ lib }:
let
  testSuffix = ".test.nix";
  failureTestSuffix = ".failure.test.nix";

  testStem = path: lib.removeSuffix testSuffix (baseNameOf path);
  failureStem = path: lib.removeSuffix failureTestSuffix (baseNameOf path);
in
{
  discover =
    sourceRoots:
    lib.concatMap (
      sourceRoot: builtins.filter sourceRoot.include (lib.filesystem.listFilesRecursive sourceRoot.path)
    ) sourceRoots;

  classify =
    files:
    let
      failureTestFiles = builtins.filter (path: lib.hasSuffix failureTestSuffix (baseNameOf path)) files;
      testFiles = builtins.filter (
        path:
        lib.hasSuffix testSuffix (baseNameOf path) && !lib.hasSuffix failureTestSuffix (baseNameOf path)
      ) files;
    in
    {
      inherit failureTestFiles testFiles;
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
