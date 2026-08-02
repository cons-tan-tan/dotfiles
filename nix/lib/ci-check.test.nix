{ lib }:
let
  ciCheck = import ./ci-check.nix { inherit lib; };
  linuxSystem = "x86_64-linux";
  darwinSystem = "aarch64-darwin";
  fakeCheck = {
    drvPath = "/nix/store/00000000000000000000000000000000-ci-check.drv";
    meta.description = "preserved metadata";
    system = linuxSystem;
  };
  evaluates = value: (builtins.tryEval (builtins.deepSeq value true)).success;
in
{
  testAnnotationPreservesMetadata = {
    expr = (ciCheck.annotate (ciCheck.targets.both "eval-tests") fakeCheck).meta.description;
    expected = "preserved metadata";
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
      ciCheck.mkHestiaJobs {
        ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.both "eval-tests") fakeCheck;
        ${darwinSystem} = { };
      }
    );
    expected = false;
  };

  testCrossSystemTargetsMustMatch = {
    expr = evaluates (
      ciCheck.mkHestiaJobs {
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
