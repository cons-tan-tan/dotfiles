{
  den,
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expectedProgram = lib.getExe pkgs.dotfilesPackages.difit;
  targets = (import ../../../flake/_interface/configuration-targets.nix { inherit lib; }) {
    inherit den system;
  };
  hostPkgs =
    if pkgs.stdenv.hostPlatform.isDarwin then
      flake.darwinConfigurations.${targets.darwin}.pkgs
    else
      flake.nixosConfigurations.${targets.nixosWsl}.pkgs;
  homePkgs =
    if pkgs.stdenv.hostPlatform.isDarwin then
      hostPkgs
    else
      flake.homeConfigurations.${targets.home.linux}.pkgs;
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    { den, ... }:
    {
      imports = [
        inputs.den.flakeModule
        ../../../flake/den-output-routing.nix
        ../../../flake/systems.nix
        ../../nixpkgs
      ];

      den.aspects.routing-probe = {
        apps =
          { pkgs, ... }:
          {
            probe = {
              type = "app";
              program = lib.getExe pkgs.dotfilesPackages.difit;
              meta.description = "Den app routing probe";
            };
          };

        devShells =
          { pkgs, ... }:
          {
            probe = pkgs.mkShell {
              packages = [ pkgs.dotfilesPackages.difit ];
            };
          };
      };

      den.schema.flake-parts.includes = [ den.aspects.routing-probe ];
    }
  );
in
{
  testAppsUseFlakePartsOverlayPackageContext = {
    expr = fixture.apps.${system}.probe.program;
    expected = expectedProgram;
  };

  testDevShellsUseFlakePartsOverlayPackageContext = {
    expr = fixture.devShells.${system}.probe.drvPath;
    expected =
      (pkgs.mkShell {
        packages = [ pkgs.dotfilesPackages.difit ];
      }).drvPath;
  };

  testHostConfigurationUsesSamePackage = {
    expr = hostPkgs.dotfilesPackages.difit.drvPath;
    expected = pkgs.dotfilesPackages.difit.drvPath;
  };

  testHomeConfigurationUsesSamePackage = {
    expr = homePkgs.dotfilesPackages.difit.drvPath;
    expected = pkgs.dotfilesPackages.difit.drvPath;
  };

  testFixtureDoesNotPublishPackages = {
    expr = builtins.attrNames (fixture.packages.${system} or { });
    expected = [ ];
  };
}
