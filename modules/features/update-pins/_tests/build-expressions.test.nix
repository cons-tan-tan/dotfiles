{
  inputs,
  lib,
  pkgs,
}:
let
  repoRoot = ../../../..;
  agentPackageSources = import ../../agents/_interface/package-sources.nix;
  system = pkgs.stdenv.hostPlatform.system;
  getInputFlake = _: { inherit inputs; };
  getEnvFrom = values: name: values.${name} or (throw "missing test environment ${name}");

  localPackage = import ../_packages/update-pins/src/nix/local-package.nix {
    inherit repoRoot system;
    getFlake = getInputFlake;
    getEnv = getEnvFrom { UPDATE_PINS_PACKAGE = "shellfirm"; };
  };

  checkProbe = pkgs.writeText "update-pins-check-expression-probe" "ok";
  localCheck = import ../_packages/update-pins/src/nix/local-check.nix {
    inherit repoRoot system;
    getFlake = _: {
      checks.${system}.probe = checkProbe;
    };
    getEnv = getEnvFrom { UPDATE_PINS_CHECK = "probe"; };
  };

  rawDifitPin = lib.importJSON (agentPackageSources.difit + "/pin.json");
  difitDependencyProvenance = {
    kind = "upstream-pnpm";
    lockPath = "pnpm-lock.yaml";
    workspacePath = "pnpm-workspace.yaml";
    workspace = "difit";
    pnpmMajor = 11;
    scope = "production";
  };
  candidatePackage = import ../_packages/update-pins/src/nix/candidate-package.nix {
    inherit repoRoot system;
    getFlake = getInputFlake;
    getEnv = getEnvFrom {
      UPDATE_PINS_PACKAGE = "difit";
      UPDATE_PINS_PIN_OVERRIDE = "difitPin";
      UPDATE_PINS_DEPENDENCY_HASH_FIELD = "pnpmDepsHash";
      UPDATE_PINS_DEPENDENCY_PROVENANCE_JSON = builtins.toJSON difitDependencyProvenance;
      UPDATE_PINS_PIN_JSON = builtins.toJSON rawDifitPin;
    };
  };
in
{
  testLocalPackageExpressionUsesFeaturePackageSet = {
    expr = localPackage.drvPath;
    expected = pkgs.dotfilesPackages.shellfirm.drvPath;
  };

  testLocalCheckExpressionSelectsSystemCheck = {
    expr = localCheck.drvPath;
    expected = checkProbe.drvPath;
  };

  testCandidateExpressionUsesFeatureCandidateBuilder = {
    expr = {
      dependencyHash = candidatePackage.pnpmDeps.outputHash;
      sourceHash = candidatePackage.src.outputHash;
    };
    expected = {
      dependencyHash = lib.fakeHash;
      sourceHash = rawDifitPin.srcHash;
    };
  };
}
