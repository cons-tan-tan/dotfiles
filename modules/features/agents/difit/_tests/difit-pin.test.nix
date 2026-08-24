{ lib, pkgs }:
let
  defaultPackage = pkgs.dotfilesPackages.difit;
in
{
  testDifitPnpmProductionScopePropagates = {
    expr = {
      package = {
        inherit (defaultPackage) pnpmInstallFlags pnpmWorkspaces;
      };
      dependencies = {
        inherit (defaultPackage.pnpmDeps) pnpmInstallFlags pnpmWorkspaces;
      };
    };
    expected = {
      package = {
        pnpmInstallFlags = [ "--prod" ];
        pnpmWorkspaces = [ "difit" ];
      };
      dependencies = {
        pnpmInstallFlags = [ "--prod" ];
        pnpmWorkspaces = [ "difit" ];
      };
    };
  };

  testDifitPnpmFetcherContractPropagates = {
    expr =
      defaultPackage.pnpmDeps.fetcherVersion == 4
      && lib.hasPrefix "pnpm-11." defaultPackage.pnpmDeps.pnpm.name
      && defaultPackage.postPatch == defaultPackage.pnpmDeps.postPatch
      && lib.hasInfix "pnpm-lock.yaml" defaultPackage.postPatch
      && lib.hasInfix "pnpm-workspace.yaml" defaultPackage.postPatch;
    expected = true;
  };

  testDifitPnpmToolchainPropagates = {
    expr =
      (
        !pkgs.stdenv.hostPlatform.isDarwin
        || lib.versions.major defaultPackage.pnpmDeps.pnpm.nodejs-slim.version == "26"
      )
      && lib.any (
        input: (input.drvPath or null) == defaultPackage.pnpmDeps.pnpm.drvPath
      ) defaultPackage.nativeBuildInputs;
    expected = true;
  };
}
