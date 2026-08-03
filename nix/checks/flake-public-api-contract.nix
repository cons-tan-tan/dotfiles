{
  apps,
  darwinConfigurations,
  devShells,
  formatter,
  homeConfigurations,
  lib,
  nixosConfigurations,
  pkgs,
  rootPackagesPresent,
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
      invalidApps
      invalidDevShells
      invalidFormatters
      rootPackagesPresent
      ;
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
    invalidApps = [ ];
    invalidDevShells = [ ];
    invalidFormatters = [ ];
    rootPackagesPresent = false;
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
