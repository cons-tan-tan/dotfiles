{ lib, pkgs }:
let
  fixtureLib = lib // {
    hm.dag.entryAfter = after: data: { inherit after data; };
  };
  deploy = import ../_interface/deploy.nix {
    lib = fixtureLib;
    inherit pkgs;
  };
  activation = deploy.mkActivation {
    after = [ "writeBoundary" ];
    name = "fixture";
    root = "/mnt/c/Users/test";
    resources = {
      fixture = {
        directories = [ ".config/tool" ];
        files = [
          {
            source = "/nix/store/source";
            destination = ".config/tool/settings";
            mode = "0600";
          }
        ];
        trees = [ ];
      };
    };
  };
  activationData = builtins.unsafeDiscardStringContext activation.data;
  packageExe = builtins.unsafeDiscardStringContext (lib.getExe deploy.package);
in
{
  testUsesWriteBoundaryAndHomeManagerRunWrapper = {
    expr = {
      inherit (activation) after;
      invokesPackage = lib.hasInfix "run ${packageExe}" activationData;
      usesManifest = lib.hasInfix "windows-fixture-deploy.json" activationData;
    };
    expected = {
      after = [ "writeBoundary" ];
      invokesPackage = true;
      usesManifest = true;
    };
  };

  testDeploymentPackageIsStoreClosed = {
    expr = {
      derivation = lib.isDerivation deploy.package;
      executable = lib.getExe deploy.package;
    };
    expected = {
      derivation = true;
      executable = "${deploy.package}/bin/windows-companion-deploy";
    };
  };
}
