{ lib, pkgs }:
let
  pin = {
    srcHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    pnpmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
  };
  injectedPackage = pkgs.dotfilesPackages.difit.override { difitPin = pin; };
  defaultPin = lib.importJSON ../_packages/difit/pin.json;
  defaultPackage = pkgs.dotfilesPackages.difit;
in
{
  testDifitPinPropagates = {
    expr = {
      injected = {
        src = injectedPackage.src.outputHash;
        pnpmDeps = injectedPackage.pnpmDeps.outputHash;
      };
      default = {
        src = defaultPackage.src.outputHash;
        pnpmDeps = defaultPackage.pnpmDeps.outputHash;
      };
    };
    expected = {
      injected = {
        src = pin.srcHash;
        pnpmDeps = pin.pnpmDepsHash;
      };
      default = {
        src = defaultPin.srcHash;
        pnpmDeps = defaultPin.pnpmDepsHash;
      };
    };
  };

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
