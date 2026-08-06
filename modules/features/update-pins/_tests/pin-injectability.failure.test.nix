{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  expectedDependencyProvenance = {
    kind = "upstream-pnpm";
    lockPath = "pnpm-lock.yaml";
    workspacePath = "pnpm-workspace.yaml";
    workspace = "difit";
    pnpmMajor = 10;
    scope = "production";
  };
  actualDependencyProvenance = expectedDependencyProvenance // {
    pnpmMajor = 11;
  };
  pkgs = {
    lib.fakeHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    dotfilesPackages.difit = {
      updatePinsDependencyProvenance = actualDependencyProvenance;
      override = _: throw "override must not be reached after provenance mismatch";
    };
  };
  candidatePackage = import (repoRoot + "/modules/features/update-pins/_lib/candidate-package.nix") {
    inherit expectedDependencyProvenance pkgs;
    packageName = "difit";
    pinOverride = "difitPin";
    dependencyHashField = "pnpmDepsHash";
    rawPin = {
      srcHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
      pnpmDepsHash = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=";
    };
  };
  cases.mismatchedDependencyProvenance = {
    expression = builtins.seq nixpkgsPath candidatePackage.drvPath;
    expectedFragment = "update-pins dependency provenance mismatch for difit";
  };
in
if caseName == null then cases else cases.${caseName}.expression
