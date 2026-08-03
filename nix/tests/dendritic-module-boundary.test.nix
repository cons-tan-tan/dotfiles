{
  inputs,
  lib,
}:
let
  modulesRoot = ../../modules;
  allNixFiles = builtins.filter (path: lib.hasSuffix ".nix" (toString path)) (
    lib.filesystem.listFilesRecursive modulesRoot
  );
  expectedModuleFiles = builtins.filter (path: !lib.hasInfix "/_" (toString path)) allNixFiles;
  actualModuleFiles = (inputs.import-tree.withLib lib).leafs modulesRoot;
  isSupportPath =
    path: lib.hasInfix "/_tests/" (toString path) || lib.hasInfix "/_lib/" (toString path);
  supportFiles = builtins.filter isSupportPath allNixFiles;
  isNonemptyModuleValue =
    path:
    let
      value = import path;
    in
    builtins.isFunction value || (builtins.isAttrs value && builtins.attrNames value != [ ]);
in
{
  testImportTreeUsesOfficialUnderscoreBoundary = {
    expr = actualModuleFiles;
    expected = expectedModuleFiles;
  };

  testModuleAndSupportTreesDoNotIntersect = {
    expr = lib.intersectLists actualModuleFiles supportFiles;
    expected = [ ];
  };

  testPureTestsUseSupportDirectories = {
    expr = builtins.all isSupportPath (
      builtins.filter (path: lib.hasSuffix ".test.nix" (toString path)) allNixFiles
    );
    expected = true;
  };

  testAutoImportedFilesHaveModuleValues = {
    expr = builtins.all isNonemptyModuleValue actualModuleFiles;
    expected = true;
  };

  testPureTestsAreNotAutoImported = {
    expr = builtins.filter (path: lib.hasSuffix ".test.nix" (toString path)) actualModuleFiles;
    expected = [ ];
  };
}
