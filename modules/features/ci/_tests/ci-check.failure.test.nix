{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  lib = import (nixpkgsPath + "/lib");
  ciCheck = import (repoRoot + "/modules/features/ci/_interface/check.nix") { inherit lib; };
  linuxSystem = "x86_64-linux";
  darwinSystem = "aarch64-darwin";
  additionalSystem = "aarch64-linux";
  fakeCheck = {
    drvPath = "/nix/store/00000000000000000000000000000000-ci-check.drv";
    meta.description = "preserved metadata";
    system = linuxSystem;
  };
  force = value: builtins.deepSeq value true;
  cases = {
    executionClassificationIsExclusive = {
      expression = force (
        ciCheck.annotate (ciCheck.targets.linux "eval-tests") (ciCheck.evaluationComplete fakeCheck)
      );
      expectedFragment = "CI check already has CI or canonical Hestia metadata";
    };

    manualConflictingMetadata = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = fakeCheck // {
            meta = fakeCheck.meta // {
              dotfiles = {
                ci.execution = "evaluation-complete";
                hestia.targets = ciCheck.targets.linux "eval-tests";
              };
            };
          };
        }
      );
      expectedFragment = "CI check has conflicting execution metadata";
    };

    evaluationCompleteRejectsCanonicalHestiaGroup = {
      expression = force (
        ciCheck.evaluationComplete (
          fakeCheck
          // {
            meta = fakeCheck.meta // {
              hestia.group = "linux-eval-tests";
            };
          }
        )
      );
      expectedFragment = "CI check already has CI or canonical Hestia metadata";
    };

    unknownExecution = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = fakeCheck // {
            meta = fakeCheck.meta // {
              dotfiles.ci.execution = "sometimes-build";
            };
          };
        }
      );
      expectedFragment = ''"missing":["example"]'';
    };

    buildSelectionRejectsStaleNames = {
      expression = force (
        ciCheck.selectBuildChecks {
          checks.build = fakeCheck;
          evaluationCompleteCheckNames = [ "renamed" ];
          system = linuxSystem;
        }
      );
      expectedFragment = ''evaluation-complete CI checks are missing for x86_64-linux: ["renamed"]'';
    };

    evaluationCompleteListingRequiresMarker = {
      expression = force (
        ciCheck.validateEvaluationCompleteChecks {
          checksBySystem = {
            ${linuxSystem}.missingMarker = fakeCheck;
            ${darwinSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ "missingMarker" ];
            ${darwinSystem} = [ ];
          };
        }
      );
      expectedFragment = ''"listedWithoutMarker":["missingMarker"]'';
    };

    evaluationCompleteListingRejectsUnknownNames = {
      expression = force (
        ciCheck.validateEvaluationCompleteChecks {
          checksBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ "unknown" ];
            ${darwinSystem} = [ ];
          };
        }
      );
      expectedFragment = ''"unknown":["unknown"]'';
    };

    evaluationCompleteListingRejectsDuplicateOwners = {
      expression = force (
        ciCheck.validateEvaluationCompleteChecks {
          checksBySystem = {
            ${linuxSystem}.evaluated = ciCheck.evaluationComplete fakeCheck;
            ${darwinSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [
              "evaluated"
              "evaluated"
            ];
            ${darwinSystem} = [ ];
          };
        }
      );
      expectedFragment = ''"duplicateNames":["evaluated"]'';
    };

    evaluationCompleteProducerRejectsDuplicateNames = {
      expression = force (
        (ciCheck.composeEvaluationCompleteProducers [
          {
            owner = "alpha";
            checks.shared = throw "alpha value must not be forced";
          }
          {
            owner = "beta";
            checks.shared = throw "beta value must not be forced";
          }
        ]).checkNames
      );
      expectedFragment = ''evaluation-complete check producer collisions: [{"name":"shared","owners":["alpha","beta"]}]'';
    };

    additionalHestiaBuildSystem = {
      expression = force (
        ciCheck.mkHestiaJobs {
          ${linuxSystem} = { };
          ${darwinSystem} = { };
          ${additionalSystem} = { };
        }
      );
      expectedFragment = "Hestia jobs must provide every build system";
    };

    missingAnnotation = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.unclassified = fakeCheck;
        }
      );
      expectedFragment = ''"missing":["unclassified"]'';
    };

    incompleteTargets = {
      expression = force (ciCheck.annotate { ${linuxSystem} = "eval-tests"; } fakeCheck);
      expectedFragment = "CI check targets must classify every build system";
    };

    unknownGroup = {
      expression = force (ciCheck.annotate (ciCheck.targets.both "unknown-group") fakeCheck);
      expectedFragment = "CI check targets contain invalid groups for systems";
    };

    allNullTargets = {
      expression = force (
        ciCheck.annotate (ciCheck.targets.bySystem {
          darwin = null;
          linux = null;
        }) fakeCheck
      );
      expectedFragment = "CI check targets must select at least one build system";
    };

    wrongDerivationSystem = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = darwinSystem;
          checks.example = ciCheck.annotate (ciCheck.targets.darwin "eval-tests") fakeCheck;
        }
      );
      expectedFragment = ''"wrongSystem":["example"]'';
    };

    declaredTargetMustExist = {
      expression = force (
        ciCheck.validateHestiaJobs {
          ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.both "eval-tests") fakeCheck;
          ${darwinSystem} = { };
        }
      );
      expectedFragment = ''"declaredButMissing":["aarch64-darwin.example"]'';
    };

    crossSystemTargetsMustMatch = {
      expression = force (
        ciCheck.validateHestiaJobs {
          ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
          ${darwinSystem}.example = ciCheck.annotate (ciCheck.targets.darwin "eval-tests") (
            fakeCheck
            // {
              system = darwinSystem;
            }
          );
        }
      );
      expectedFragment = ''"inconsistent":["example"]'';
    };

    conflictingDerivationGroups = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks = {
            first = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
            second = ciCheck.annotate (ciCheck.targets.linux "package-smoke") fakeCheck;
          };
        }
      );
      expectedFragment = ''"conflictingDrvPaths":["/nix/store/00000000000000000000000000000000-ci-check.drv"]'';
    };

    canonicalHestiaGroup = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = fakeCheck // {
            meta = fakeCheck.meta // {
              hestia.group = "linux-eval-tests";
              dotfiles.hestia.targets = ciCheck.targets.linux "eval-tests";
            };
          };
        }
      );
      expectedFragment = "canonical checks must not define meta.hestia.group";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
