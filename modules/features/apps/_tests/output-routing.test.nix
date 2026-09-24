{
  inputs,
  lib,
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  fixture = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ../../../flake/systems.nix
      ../../nixpkgs
    ];
    perSystem = { pkgs, ... }: {
      apps.probe = {
        type = "app";
        program = lib.getExe pkgs.dotfilesPackages.difit;
        meta.description = "App package context probe";
      };
      devShells.probe = pkgs.mkShell { packages = [ pkgs.dotfilesPackages.difit ]; };
      checks.probe = pkgs.dotfilesPackages.difit;
    };
  };
in
{
  testAppsUseOverlayPackageContext = {
    expr = fixture.apps.${system}.probe.program;
    expected = lib.getExe pkgs.dotfilesPackages.difit;
  };
  testDevShellsUseOverlayPackageContext = {
    expr = fixture.devShells.${system}.probe.drvPath;
    expected = (pkgs.mkShell { packages = [ pkgs.dotfilesPackages.difit ]; }).drvPath;
  };
  testChecksUseOverlayPackageContext = {
    expr = fixture.checks.${system}.probe.drvPath;
    expected = pkgs.dotfilesPackages.difit.drvPath;
  };
  testChecksHaveSingleRootRoute = {
    expr = builtins.attrNames fixture.checks.${system};
    expected = [ "probe" ];
  };
}
