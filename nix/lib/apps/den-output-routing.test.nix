{
  flake,
  inputs,
  lib,
  pkgs,
  username,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expectedProgram = lib.getExe pkgs.dotfilesPackages.difit;
  configNames = import ../../../modules/entities/_lib/configuration-names.nix { inherit username; };
  hostPkgs =
    if pkgs.stdenv.hostPlatform.isDarwin then
      flake.darwinConfigurations.${username}.pkgs
    else
      flake.nixosConfigurations.${configNames.forNixosWsl { inherit system; }}.pkgs;
  homePkgs =
    if pkgs.stdenv.hostPlatform.isDarwin then
      hostPkgs
    else
      flake.homeConfigurations.${
        configNames.forHost {
          hostKind = "linux";
          inherit system;
        }
      }.pkgs;
  expectedCommonApps = (import ./mk-common-apps.nix { inherit inputs username; }) {
    inherit pkgs;
    treefmtWrapper = flake.formatter.${system};
  };

  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    { den, ... }:
    {
      imports = [
        inputs.den.flakeModule
        ../../../modules/flake/den-output-routing.nix
        ../../../modules/flake/systems.nix
        ../../../modules/features/nixpkgs.nix
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
  testAppsUseFlakePartsPkgs = {
    expr = fixture.apps.${system}.probe.program;
    expected = expectedProgram;
  };

  testDevShellsUseFlakePartsPkgs = {
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
