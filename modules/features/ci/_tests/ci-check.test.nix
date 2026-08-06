{ lib }:
let
  ciCheck = import ../_interface/check.nix { inherit lib; };
  linuxSystem = "x86_64-linux";
  darwinSystem = "aarch64-darwin";
  fakeCheck = {
    drvPath = "/nix/store/00000000000000000000000000000000-ci-check.drv";
    meta.description = "preserved metadata";
    system = linuxSystem;
  };
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

  testEvaluationCompleteProducerIndexDoesNotForceChecks = {
    expr =
      (ciCheck.composeEvaluationCompleteProducers [
        {
          owner = "fixture";
          checks.evaluated = throw "evaluation-complete producer value was forced";
        }
      ]).checkNames;
    expected = [ "evaluated" ];
  };

  testEvaluationCompleteProducerRealizesCheckMetadata = {
    expr =
      let
        composition = ciCheck.composeEvaluationCompleteProducers [
          {
            owner = "fixture";
            checks.evaluated = fakeCheck;
          }
        ];
      in
      {
        names = composition.checkNames;
        classified = ciCheck.isEvaluationComplete composition.checks.evaluated;
        description = composition.checks.evaluated.meta.description;
      };
    expected = {
      names = [ "evaluated" ];
      classified = true;
      description = "preserved metadata";
    };
  };

  testEvaluationCompleteProducerKeepsRawValuesUnclassified = {
    expr =
      let
        composition = ciCheck.composeEvaluationCompleteProducers [
          {
            owner = "fixture";
            checks.evaluated = fakeCheck;
          }
        ];
      in
      {
        classified = ciCheck.isClassified composition.values.evaluated;
        description = composition.values.evaluated.meta.description;
      };
    expected = {
      classified = false;
      description = "preserved metadata";
    };
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

  testValidationDoesNotForceUnlistedBuildChecks = {
    expr = ciCheck.validateEvaluationCompleteChecks {
      checksBySystem = {
        ${linuxSystem}.build = throw "unlisted build check was forced";
        ${darwinSystem} = { };
      };
      evaluationCompleteCheckNamesBySystem = {
        ${linuxSystem} = [ ];
        ${darwinSystem} = [ ];
      };
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

  testSystemPartitionDoesNotForceSiblingChecks = {
    expr = builtins.attrNames (
      (ciCheck.mkHestiaJobs {
        ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
        ${darwinSystem} = throw "sibling system was forced";
      }).${linuxSystem}
    );
    expected = [ "example" ];
  };
}
