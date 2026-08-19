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
  withTargets =
    targets:
    fakeCheck
    // {
      meta = fakeCheck.meta // {
        dotfiles.hestia.targets = targets;
      };
    };
  force = value: builtins.deepSeq value true;
  checkDefinitions =
    modules:
    (lib.evalModules {
      modules = [
        {
          options.checks = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = { };
          };
        }
      ]
      ++ modules;
    }).options.checks.definitionsWithLocations;
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

    evaluationCompleteRejectsExistingExecutionMetadata = {
      expression = force (
        ciCheck.evaluationComplete (
          fakeCheck
          // {
            meta = fakeCheck.meta // {
              dotfiles.ci.execution = "evaluation-complete";
            };
          }
        )
      );
      expectedFragment = "CI check already has CI or canonical Hestia metadata";
    };

    annotationRejectsLegacyHestiaMetadata = {
      expression = force (
        ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          fakeCheck
          // {
            meta = fakeCheck.meta // {
              dotfiles.hestia = { };
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
      expectedFragment = ''"invalidRoutes":["example"]'';
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

    evaluationCompleteProducerMustBeAnAttributeSet = {
      expression = force ((ciCheck.composeEvaluationCompleteProducers [ "invalid" ]).checkNames);
      expectedFragment = "invalid evaluation-complete check producers: [0]";
    };

    evaluationCompleteProducerOwnerMustBeAString = {
      expression = force (
        (ciCheck.composeEvaluationCompleteProducers [
          {
            owner = 1;
            checks = { };
          }
        ]).checkNames
      );
      expectedFragment = "invalid evaluation-complete check producers: [0]";
    };

    evaluationCompleteProducerOwnerMustNotBeEmpty = {
      expression = force (
        (ciCheck.composeEvaluationCompleteProducers [
          {
            owner = "";
            checks = { };
          }
        ]).checkNames
      );
      expectedFragment = "invalid evaluation-complete check producers: [0]";
    };

    evaluationCompleteProducerChecksMustBeAnAttributeSet = {
      expression = force (
        (ciCheck.composeEvaluationCompleteProducers [
          {
            owner = "fixture";
            checks = "invalid";
          }
        ]).checkNames
      );
      expectedFragment = "invalid evaluation-complete check producers: [0]";
    };

    evaluationManifestRejectsUnknownName = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ "unknown" ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = ''"unknown":["unknown"]'';
    };

    evaluationManifestRejectsDuplicateName = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ "evaluated" ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [
              "evaluated"
              "evaluated"
            ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = ''"duplicateNames":["evaluated"]'';
    };

    buildManifestRejectsMissingRoute = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ "unrouted" ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = ''"missing":["unrouted"]'';
    };

    buildManifestRejectsUnexpectedRoute = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem}.stale = ciCheck.targets.linux "eval-tests";
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = ''"unexpected":["stale"]'';
    };

    buildManifestRejectsMissingDeclaredSystem = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ "example" ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem}.example = ciCheck.targets.both "eval-tests";
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = ''"declaredButMissing":["aarch64-darwin.example"]'';
    };

    buildManifestRejectsInconsistentTargets = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ "example" ];
            ${darwinSystem} = [ "example" ];
            ${additionalSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem}.example = ciCheck.targets.linux "eval-tests";
            ${darwinSystem}.example = ciCheck.targets.darwin "eval-tests";
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = ''"inconsistent":["example"]'';
    };

    buildManifestRejectsUnmirroredAdditionalSystemCheck = {
      expression = force (
        ciCheck.validateCheckManifest {
          checkNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ "arm-only" ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          buildRoutesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
            ${additionalSystem}.arm-only = ciCheck.targets.linux "eval-tests";
          };
        }
      );
      expectedFragment = ''"declaredButMissing":["x86_64-linux.arm-only"]'';
    };

    additionalHestiaBuildSystem = {
      expression = force (
        ciCheck.mkHestiaJobs {
          checksBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
            ${additionalSystem} = [ ];
          };
          routesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
            ${additionalSystem} = { };
          };
        }
      );
      expectedFragment = "Hestia jobs must provide every build system";
    };

    hestiaJobsRejectRouteMetadataMismatch = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = ciCheck.annotate (ciCheck.targets.darwin "eval-tests") fakeCheck;
          routes.example = ciCheck.targets.linux "eval-tests";
        }
      );
      expectedFragment = ''"metadataMismatch":["example"]'';
    };

    hestiaJobsValidateChecksExcludedFromCurrentSystem = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks = {
            excluded = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
            selected = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
          };
          routes = {
            excluded = ciCheck.targets.darwin "eval-tests";
            selected = ciCheck.targets.linux "eval-tests";
          };
        }
      );
      expectedFragment = ''"metadataMismatch":["excluded"]'';
    };

    evaluationCompleteDefinitionsRejectForcedLeaf = {
      expression = force (
        ciCheck.validateEvaluationCompleteDefinitions {
          checkDefinitionsBySystem.${linuxSystem} = checkDefinitions [
            {
              _file = "owner";
              checks.evaluated = throw "owned check must stay lazy";
            }
            {
              _file = "override";
              checks.evaluated = lib.mkForce fakeCheck;
            }
          ];
          evaluationCompleteCheckNamesBySystem.${linuxSystem} = [ "evaluated" ];
          expectedFile = "owner";
        }
      );
      expectedFragment = ''"multiplyDefined":["evaluated"]'';
    };

    evaluationCompleteDefinitionsRejectForcedSet = {
      expression = force (
        ciCheck.validateEvaluationCompleteDefinitions {
          checkDefinitionsBySystem.${linuxSystem} = checkDefinitions [
            {
              _file = "owner";
              checks.evaluated = throw "owned check must stay lazy";
            }
            {
              _file = "override";
              checks = lib.mkForce { evaluated = fakeCheck; };
            }
          ];
          evaluationCompleteCheckNamesBySystem.${linuxSystem} = [ "evaluated" ];
          expectedFile = "owner";
        }
      );
      expectedFragment = ''"unexpectedOwners":[{"file":"override","name":"evaluated"}]'';
    };

    evaluationCompleteDefinitionsRejectMismatchedSystems = {
      expression = force (
        ciCheck.validateEvaluationCompleteDefinitions {
          checkDefinitionsBySystem = {
            ${linuxSystem} = [ ];
            ${darwinSystem} = [ ];
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ ];
          };
          expectedFile = "owner";
        }
      );
      expectedFragment = "evaluation-complete check definitions must use matching systems";
    };

    hestiaJobsRejectUnknownEvaluationCompleteName = {
      expression = force (
        (ciCheck.mkHestiaJobs {
          checksBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ "unknown" ];
            ${darwinSystem} = [ ];
          };
          routesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
          };
        }).${linuxSystem}
      );
      expectedFragment = ''"unknown":["unknown"]'';
    };

    hestiaJobsRejectEvaluationCompleteChecksWithoutBuildJobs = {
      expression = force (
        (ciCheck.mkHestiaJobs {
          checksBySystem = {
            ${linuxSystem}.evaluated = ciCheck.evaluationComplete fakeCheck;
            ${darwinSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ "evaluated" ];
            ${darwinSystem} = [ ];
          };
          routesBySystem = {
            ${linuxSystem} = { };
            ${darwinSystem} = { };
          };
        }).${linuxSystem}
      );
      expectedFragment = "require at least one Hestia build job";
    };

    missingAnnotation = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.unclassified = fakeCheck;
        }
      );
      expectedFragment = ''"invalidRoutes":["unclassified"]'';
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

    canonicalTargetsRejectAdditionalSystem = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = withTargets {
            ${linuxSystem} = "eval-tests";
            ${darwinSystem} = "eval-tests";
            ${additionalSystem} = "eval-tests";
          };
        }
      );
      expectedFragment = ''"invalidRoutes":["example"]'';
    };

    canonicalTargetsRejectAllNullSystems = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = withTargets {
            ${linuxSystem} = null;
            ${darwinSystem} = null;
          };
        }
      );
      expectedFragment = ''"invalidRoutes":["example"]'';
    };

    canonicalTargetsRejectUnknownGroup = {
      expression = force (
        ciCheck.mkHestiaChecks {
          system = linuxSystem;
          checks.example = withTargets {
            ${linuxSystem} = "unknown-group";
            ${darwinSystem} = null;
          };
        }
      );
      expectedFragment = ''"invalidRoutes":["example"]'';
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
