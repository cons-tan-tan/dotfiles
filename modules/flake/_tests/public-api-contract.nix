{
  apps,
  checks,
  darwinConfigurations,
  devShells,
  formatter,
  homeConfigurations,
  lib,
  nixosConfigurations,
  packages,
  pkgs,
  rootPackagesPresent,
  rootHydraCiPresent,
  systems,
}:
let
  sort = lib.sort builtins.lessThan;
  expectedSystems = sort [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  commonApps = [
    "apply-nix-settings"
    "apply-secrets"
    "build"
    "fmt"
    "markdownlint"
    "pptx"
    "switch"
    "textlint"
    "update"
    "update-pins"
  ];
  expectedApps = lib.genAttrs expectedSystems (
    system: sort (commonApps ++ lib.optional (lib.hasSuffix "-linux" system) "apply-winget")
  );
  expectedDevShells = lib.genAttrs expectedSystems (_: [
    "default"
    "rust"
  ]);
  expectedFlakeFilePackages = [
    "write-flake"
    "write-inputs"
    "write-lock"
  ];
  expectedFlakeFileCheckTargets = {
    aarch64-darwin = "repo-quality";
    x86_64-linux = "repo-quality";
  };
  commonRequiredChecks = [
    "app-scripts"
    "bats-tests"
    "check-flake-file"
    "ci-check-tests"
    "configuration-targets-tests"
    "dendritic-module-boundary-tests"
    "package-smoke-tests"
    "rust-projects-tests"
    "rust-tests"
    "test-discovery-tests"
    "treefmt"
    "workflow-policy-tests"
  ];
  linuxRequiredChecks = [
    "home-linux"
    "home-wsl"
    "nixos-wsl-contract"
    "nixos-wsl-system"
    "reuse-lint"
  ];
  expectedRequiredChecks = {
    aarch64-darwin = commonRequiredChecks ++ [
      "darwin-nh-cleanup-contract"
      "darwin-system"
    ];
    aarch64-linux = commonRequiredChecks ++ linuxRequiredChecks;
    x86_64-linux =
      commonRequiredChecks
      ++ linuxRequiredChecks
      ++ [
        "configuration-ownership-contract"
        "flake-public-api-contract"
        "home-feature-contract"
        "windows-class-contract"
      ];
  };

  appNames = lib.mapAttrs (_: value: builtins.attrNames value) apps;
  devShellNames = lib.mapAttrs (_: value: builtins.attrNames value) devShells;
  invalidApps = lib.concatMap (
    system:
    lib.concatLists (
      lib.mapAttrsToList (
        name: app:
        lib.optional (
          !builtins.isAttrs app
          || (app.type or null) != "app"
          || !(builtins.isString (app.program or null))
          || app.program == ""
          || !(builtins.isString (app.meta.description or null))
          || app.meta.description == ""
        ) "${system}.${name}"
      ) apps.${system}
    )
  ) (builtins.attrNames apps);
  invalidDevShells = lib.concatMap (
    system:
    lib.concatLists (
      lib.mapAttrsToList (
        name: shell: lib.optional (!lib.isDerivation shell) "${system}.${name}"
      ) devShells.${system}
    )
  ) (builtins.attrNames devShells);
  invalidFormatters = lib.concatLists (
    lib.mapAttrsToList (system: value: lib.optional (!lib.isDerivation value) system) formatter
  );
  invalidFlakeFileChecks = builtins.filter (
    system:
    let
      check = checks.${system}.check-flake-file or null;
    in
    !lib.isDerivation check
    || (check.meta.dotfiles.hestia.targets or null) != expectedFlakeFileCheckTargets
  ) expectedSystems;
  invalidFlakeFilePackages = lib.concatMap (
    system:
    lib.concatLists (
      lib.mapAttrsToList (
        name: package: lib.optional (!lib.isDerivation package) "${system}.${name}"
      ) packages.${system}
    )
  ) (builtins.attrNames packages);
  missingRequiredChecks = lib.mapAttrs (
    system: required: builtins.filter (name: !(builtins.hasAttr name checks.${system})) required
  ) expectedRequiredChecks;

  actual = {
    systems = sort systems;
    appSystems = builtins.attrNames apps;
    inherit appNames;
    darwinConfigurations = builtins.attrNames darwinConfigurations;
    devShellSystems = builtins.attrNames devShells;
    inherit devShellNames;
    formatterSystems = builtins.attrNames formatter;
    homeConfigurations = builtins.attrNames homeConfigurations;
    inherit
      invalidFlakeFileChecks
      invalidFlakeFilePackages
      invalidApps
      invalidDevShells
      invalidFormatters
      missingRequiredChecks
      rootHydraCiPresent
      rootPackagesPresent
      ;
    packageNames = lib.mapAttrs (_: value: builtins.attrNames value) packages;
    packageSystems = builtins.attrNames packages;
    nixosConfigurations = builtins.attrNames nixosConfigurations;
  };
  expected = {
    systems = expectedSystems;
    appSystems = expectedSystems;
    appNames = expectedApps;
    darwinConfigurations = [ "constantan" ];
    devShellSystems = expectedSystems;
    devShellNames = expectedDevShells;
    formatterSystems = expectedSystems;
    homeConfigurations = [
      "constantan@linux-aarch64"
      "constantan@linux-x86_64"
      "constantan@wsl-aarch64"
      "constantan@wsl-x86_64"
    ];
    invalidFlakeFileChecks = [ ];
    invalidFlakeFilePackages = [ ];
    invalidApps = [ ];
    invalidDevShells = [ ];
    invalidFormatters = [ ];
    missingRequiredChecks = lib.genAttrs expectedSystems (_: [ ]);
    packageNames = lib.genAttrs expectedSystems (_: expectedFlakeFilePackages);
    packageSystems = expectedSystems;
    rootPackagesPresent = true;
    rootHydraCiPresent = true;
    nixosConfigurations = [
      "wsl"
      "wsl-aarch64"
    ];
  };
in
assert lib.assertMsg (actual == expected) ''
  Flake public API contract mismatch:
  expected ${builtins.toJSON expected}
  actual ${builtins.toJSON actual}
'';
pkgs.runCommand "flake-public-api-contract" { } ''touch "$out"''
