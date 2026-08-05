{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
}:
let
  modulesRoot = repoRoot + "/modules";
  catalog = import ../_lib/rust-projects.nix {
    inherit ciCheck lib pkgs;
  };
  inherit (catalog) projects;

  sourceFiles = lib.filesystem.listFilesRecursive modulesRoot;
  relativePath = path: lib.removePrefix "${toString repoRoot}/" (toString path);
  discoveredManifests = map relativePath (
    builtins.filter (path: baseNameOf path == "Cargo.toml") sourceFiles
  );
  discoveredLockfiles = map relativePath (
    builtins.filter (path: baseNameOf path == "Cargo.lock") sourceFiles
  );
  currentInventory = catalog.inventory {
    inherit discoveredLockfiles discoveredManifests;
  };

  localProjects = builtins.filter (project: !project.advisoryOnly) projects;
  advisoryOnlyProjects = builtins.filter (project: project.advisoryOnly) projects;
  invalidLocalProjects = map (project: project.name) (
    builtins.filter (
      project:
      project.manifest == null
      || project.buildVariants == [ ]
      || project.clippyVariants == [ ]
      || !(builtins.isFunction project.platformPredicate)
    ) localProjects
  );
  invalidAdvisoryOnlyProjects = map (project: project.name) (
    builtins.filter (
      project:
      project.manifest != null
      || project.buildVariants != [ ]
      || project.clippyVariants != [ ]
      || project.packages != { }
    ) advisoryOnlyProjects
  );

  buildCheckNames = lib.concatMap (
    project: map (variant: variant.checkName) project.buildVariants
  ) projects;
  clippyCheckNames = lib.concatMap (
    project: map (variant: variant.checkName) project.clippyVariants
  ) projects;
  invalidAdvisories = lib.concatMap (
    project:
    map
      (advisory: {
        inherit (project) name;
        value = advisory;
      })
      (
        builtins.filter (
          advisory:
          !(builtins.isAttrs advisory)
          ||
            lib.sort lib.lessThan (builtins.attrNames advisory) != [
              "expiresAt"
              "id"
              "reviewedAt"
            ]
          || !(builtins.isString advisory.id)
          || advisory.id == ""
          || !(builtins.isString advisory.reviewedAt)
          || advisory.reviewedAt == ""
          || !(builtins.isInt advisory.expiresAt)
        ) project.lock.ignoredAdvisories
      )
  ) projects;
in
{
  testProjectInventory = {
    expr = currentInventory;
    expected = {
      manifests = {
        missing = [ ];
        stale = [ ];
        duplicate = [ ];
      };
      lockfiles = {
        missing = [ ];
        stale = [ ];
        duplicate = [ ];
      };
    };
  };

  testInventoryDiagnostics = {
    expr = {
      missing = catalog.inventoryDiff [ "registered/Cargo.toml" ] [ ];
      stale = catalog.inventoryDiff [ ] [ "stale/Cargo.toml" ];
      duplicate =
        catalog.inventoryDiff
          [ "duplicate/Cargo.toml" ]
          [
            "duplicate/Cargo.toml"
            "duplicate/Cargo.toml"
          ];
    };
    expected = {
      missing = {
        missing = [ "registered/Cargo.toml" ];
        stale = [ ];
        duplicate = [ ];
      };
      stale = {
        missing = [ ];
        stale = [ "stale/Cargo.toml" ];
        duplicate = [ ];
      };
      duplicate = {
        missing = [ ];
        stale = [ ];
        duplicate = [ "duplicate/Cargo.toml" ];
      };
    };
  };

  testProjectNamesAreUnique = {
    expr = catalog.duplicates (map (project: project.name) projects);
    expected = [ ];
  };

  testLocalProjectsDeclareChecks = {
    expr = invalidLocalProjects;
    expected = [ ];
  };

  testAdvisoryOnlyProjectsDeclareNoChecks = {
    expr = invalidAdvisoryOnlyProjects;
    expected = [ ];
  };

  testBuildCheckNamesAreUnique = {
    expr = catalog.duplicates buildCheckNames;
    expected = [ ];
  };

  testClippyCheckNamesAreUnique = {
    expr = catalog.duplicates clippyCheckNames;
    expected = [ ];
  };

  testIgnoredAdvisoryShape = {
    expr = invalidAdvisories;
    expected = [ ];
  };
}
