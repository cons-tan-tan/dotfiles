{
  inputs,
  lib,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  expectedProgram = lib.getExe pkgs.dotfilesPackages.difit;
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

}
