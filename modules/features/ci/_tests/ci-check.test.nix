{ lib }:
let
  ciCheck = import ../_interface/check.nix { inherit lib; };
  linuxSystem = "x86_64-linux";
  darwinSystem = "aarch64-darwin";
  additionalSystem = "aarch64-linux";
  fakeCheck = {
    drvPath = "/nix/store/00000000000000000000000000000000-ci-check.drv";
    meta.description = "preserved metadata";
    system = linuxSystem;
  };
  evaluates = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  fakeFor =
    name: system:
    fakeCheck
    // {
      drvPath = "/nix/store/00000000000000000000000000000000-${name}.drv";
      meta.description = "${name} metadata";
      inherit system;
    };
in
{
  testAnnotationPreservesMetadata = {
    expr = (ciCheck.annotate (ciCheck.targets.both "eval-tests") fakeCheck).meta.description;
    expected = "preserved metadata";
  };

  testEvaluationCompletePreservesMetadata = {
    expr = {
      classified = ciCheck.isClassified (ciCheck.evaluationComplete fakeCheck);
      evaluationComplete = ciCheck.isEvaluationComplete (ciCheck.evaluationComplete fakeCheck);
      description = (ciCheck.evaluationComplete fakeCheck).meta.description;
    };
    expected = {
      classified = true;
      evaluationComplete = true;
      description = "preserved metadata";
    };
  };

  testExecutionClassificationIsExclusive = {
    expr = evaluates (
      ciCheck.annotate (ciCheck.targets.linux "eval-tests") (ciCheck.evaluationComplete fakeCheck)
    );
    expected = false;
  };

  testManualConflictingMetadataFails = {
    expr = evaluates (
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
    expected = false;
  };

  testEvaluationCompleteRejectsCanonicalHestiaGroup = {
    expr = evaluates (
      ciCheck.evaluationComplete (
        fakeCheck
        // {
          meta = fakeCheck.meta // {
            hestia.group = "linux-eval-tests";
          };
        }
      )
    );
    expected = false;
  };

  testUnknownExecutionFails = {
    expr = evaluates (
      ciCheck.mkHestiaChecks {
        system = linuxSystem;
        checks.example = fakeCheck // {
          meta = fakeCheck.meta // {
            dotfiles.ci.execution = "sometimes-build";
          };
        };
      }
    );
    expected = false;
  };

  testBuildSelectionDoesNotForceEvaluationCompleteChecks = {
    expr = builtins.attrNames (
      ciCheck.selectBuildChecks {
        checks = {
          build = fakeCheck;
          evaluated = throw "evaluation-complete check was forced";
        };
        evaluationCompleteCheckNames = [ "evaluated" ];
        system = linuxSystem;
      }
    );
    expected = [ "build" ];
  };

  testBuildSelectionRejectsStaleNames = {
    expr = evaluates (
      ciCheck.selectBuildChecks {
        checks.build = fakeCheck;
        evaluationCompleteCheckNames = [ "renamed" ];
        system = linuxSystem;
      }
    );
    expected = false;
  };

  testEvaluationCompleteListingRequiresMarker = {
    expr = evaluates (
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
    expected = false;
  };

  testEvaluationCompleteMarkerRequiresListing = {
    expr = evaluates (
      ciCheck.validateEvaluationCompleteChecks {
        checksBySystem = {
          ${linuxSystem} = { };
          ${darwinSystem}.missingListing = ciCheck.evaluationComplete (
            fakeCheck // { system = darwinSystem; }
          );
        };
        evaluationCompleteCheckNamesBySystem = {
          ${linuxSystem} = [ ];
          ${darwinSystem} = [ ];
        };
      }
    );
    expected = false;
  };

  testEvaluationCompleteListingRejectsDuplicateOwners = {
    expr = evaluates (
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
    expected = false;
  };

  testIgnoredValidationCheckIsNotForced = {
    expr = ciCheck.validateEvaluationCompleteChecks {
      checksBySystem = {
        ${linuxSystem}.contract = throw "validation contract was forced";
        ${darwinSystem} = { };
      };
      evaluationCompleteCheckNamesBySystem = {
        ${linuxSystem} = [ "contract" ];
        ${darwinSystem} = [ ];
      };
      ignoredCheckNamesBySystem.${linuxSystem} = [ "contract" ];
    };
    expected = true;
  };

  testSystemSpecificGroups =
    let
      checkTargets = ciCheck.targets.bySystem {
        darwin = "configurations";
        linux = "repo-quality";
      };
      jobs = ciCheck.mkHestiaJobs {
        ${linuxSystem}.example = ciCheck.annotate checkTargets fakeCheck;
        ${darwinSystem}.example = ciCheck.annotate checkTargets (
          fakeCheck
          // {
            system = darwinSystem;
          }
        );
      };
    in
    {
      expr = {
        darwin = jobs.${darwinSystem}.example.meta.hestia.group;
        linux = jobs.${linuxSystem}.example.meta.hestia.group;
      };
      expected = {
        darwin = "darwin-configurations";
        linux = "linux-repo-quality";
      };
    };

  testNullTargetExcludesCheck =
    let
      checks = ciCheck.mkHestiaChecks {
        system = linuxSystem;
        checks = {
          excluded = ciCheck.annotate (ciCheck.targets.darwin "eval-tests") fakeCheck;
          included = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
        };
      };
    in
    {
      expr = builtins.attrNames checks;
      expected = [ "included" ];
    };

  testCanonicalSelectionPreservesMetadata =
    let
      bothTargets = ciCheck.targets.both "eval-tests";
      linuxTargets = ciCheck.targets.linux "repo-quality";
      darwinTargets = ciCheck.targets.darwin "configurations";
      jobs = ciCheck.mkHestiaJobs {
        ${linuxSystem} = {
          both = ciCheck.annotate bothTargets (fakeFor "both-linux" linuxSystem);
          linuxOnly = ciCheck.annotate linuxTargets (fakeFor "linux-only" linuxSystem);
        };
        ${darwinSystem} = {
          both = ciCheck.annotate bothTargets (fakeFor "both-darwin" darwinSystem);
          darwinOnly = ciCheck.annotate darwinTargets (fakeFor "darwin-only" darwinSystem);
        };
      };
    in
    {
      expr = {
        linuxNames = builtins.attrNames jobs.${linuxSystem};
        darwinNames = builtins.attrNames jobs.${darwinSystem};
        linuxGroup = jobs.${linuxSystem}.linuxOnly.meta.hestia.group;
        darwinGroup = jobs.${darwinSystem}.darwinOnly.meta.hestia.group;
        description = jobs.${linuxSystem}.both.meta.description;
        targets = jobs.${darwinSystem}.both.meta.dotfiles.hestia.targets;
      };
      expected = {
        linuxNames = [
          "both"
          "linuxOnly"
        ];
        darwinNames = [
          "both"
          "darwinOnly"
        ];
        linuxGroup = "linux-repo-quality";
        darwinGroup = "darwin-configurations";
        description = "both-linux metadata";
        targets = bothTargets;
      };
    };

  testAdditionalHestiaBuildSystemFails = {
    expr = evaluates (
      ciCheck.mkHestiaJobs {
        ${linuxSystem} = { };
        ${darwinSystem} = { };
        ${additionalSystem} = { };
      }
    );
    expected = false;
  };

  testMissingAnnotationFails = {
    expr = evaluates (
      ciCheck.mkHestiaChecks {
        system = linuxSystem;
        checks.unclassified = fakeCheck;
      }
    );
    expected = false;
  };

  testIncompleteTargetsFail = {
    expr = evaluates (ciCheck.annotate { ${linuxSystem} = "eval-tests"; } fakeCheck);
    expected = false;
  };

  testUnknownGroupFails = {
    expr = evaluates (ciCheck.annotate (ciCheck.targets.both "unknown-group") fakeCheck);
    expected = false;
  };

  testAllNullTargetsFail = {
    expr = evaluates (
      ciCheck.annotate (ciCheck.targets.bySystem {
        darwin = null;
        linux = null;
      }) fakeCheck
    );
    expected = false;
  };

  testWrongDerivationSystemFails = {
    expr = evaluates (
      ciCheck.mkHestiaChecks {
        system = darwinSystem;
        checks.example = ciCheck.annotate (ciCheck.targets.darwin "eval-tests") fakeCheck;
      }
    );
    expected = false;
  };

  testDeclaredTargetMustExist = {
    expr = evaluates (
      ciCheck.validateHestiaJobs {
        ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.both "eval-tests") fakeCheck;
        ${darwinSystem} = { };
      }
    );
    expected = false;
  };

  testCrossSystemTargetsMustMatch = {
    expr = evaluates (
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
    expected = false;
  };

  testSystemPartitionDoesNotForceSiblingChecks = {
    expr = builtins.attrNames (
      (ciCheck.mkHestiaJobs {
        ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
        ${darwinSystem} = throw "sibling system was forced";
      }).${linuxSystem}
    );
    expected = [ "example" ];
  };

  testConflictingDerivationGroupsFail = {
    expr = evaluates (
      ciCheck.mkHestiaChecks {
        system = linuxSystem;
        checks = {
          first = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
          second = ciCheck.annotate (ciCheck.targets.linux "package-smoke") fakeCheck;
        };
      }
    );
    expected = false;
  };

  testCanonicalHestiaGroupFails = {
    expr = evaluates (
      ciCheck.mkHestiaChecks {
        system = linuxSystem;
        checks.example = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          fakeCheck
          // {
            meta = fakeCheck.meta // {
              hestia.group = "linux-eval-tests";
            };
          }
        );
      }
    );
    expected = false;
  };
}
