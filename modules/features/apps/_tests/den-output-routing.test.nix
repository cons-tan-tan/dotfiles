{
  den,
  flake,
  inputs,
  lib,
  pkgs,
}:
let
  expectedUsername = "constantan";
  system = pkgs.stdenv.hostPlatform.system;
  expectedProgram = lib.getExe pkgs.dotfilesPackages.difit;
  targets = (import ../../../entities/_lib/configuration-targets.nix { inherit lib; }) {
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
  expectedCommonApps =
    (import ../../../../nix/lib/apps/mk-common-apps.nix {
      inherit inputs;
      username = expectedUsername;
    })
      {
        inherit pkgs;
        treefmtWrapper = flake.formatter.${system};
      };

  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    { den, ... }:
    {
      imports = [
        inputs.den.flakeModule
        ../../../flake/den-output-routing.nix
        ../../../flake/systems.nix
        ../../nixpkgs.nix
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

  testPublicAppUsesSamePackageSet = {
    expr = flake.apps.${system}.update-pins.program;
    expected = expectedCommonApps.apps.update-pins.program;
  };

  testFixtureDoesNotPublishPackages = {
    expr = builtins.attrNames (fixture.packages.${system} or { });
    expected = [ ];
  };
}
