{
  ciCheck,
  lib,
  pkgs,
}:
let
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

  projects = import ./rust-fragments.nix { inherit ciCheck pkgs; };
in
{
  inherit
    duplicates
    inventory
    inventoryDiff
    projects
    ;
}
