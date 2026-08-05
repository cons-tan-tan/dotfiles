{
  ciCheck,
  lib,
  pkgs,
}:
let
  featuresRoot = ../..;
  difference = left: right: builtins.filter (value: !(builtins.elem value right)) left;
  duplicates =
    values:
    builtins.filter (
      value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
    ) (lib.unique values);
  inventoryDiff = discovered: declared: {
    missing = difference discovered declared;
    stale = difference declared discovered;
    duplicate = duplicates declared;
  };
  inventory =
    {
      discoveredManifests,
      discoveredLockfiles,
      projectList ? projects,
    }:
    let
      declaredManifests = builtins.filter (path: path != null) (
        map (project: project.manifest) projectList
      );
      declaredLockfiles = map (project: project.lock.path) projectList;
    in
    {
      manifests = inventoryDiff discoveredManifests declaredManifests;
      lockfiles = inventoryDiff discoveredLockfiles declaredLockfiles;
    };

  projectFiles = lib.sort builtins.lessThan (
    builtins.filter (
      path:
      lib.hasInfix "/_tests/" (toString path)
      && builtins.elem (baseNameOf path) [
        "rust-project.nix"
        "rust-projects.nix"
      ]
    ) (lib.filesystem.listFilesRecursive featuresRoot)
  );
  loadProjects =
    path:
    let
      declaration = import path { inherit ciCheck pkgs; };
      projectsForOwner = if builtins.isList declaration then declaration else [ declaration ];
    in
    if
      projectsForOwner != [ ]
      && builtins.all (
        project: builtins.isAttrs project && builtins.isAttrs (project.subjects or { })
      ) projectsForOwner
    then
      projectsForOwner
    else
      throw "${toString path} must declare a Rust project, or a non-empty list of Rust projects, with an optional subjects attrset";
  projects = lib.concatMap loadProjects projectFiles;
in
{
  inherit
    duplicates
    inventory
    inventoryDiff
    projectFiles
    projects
    ;
}
