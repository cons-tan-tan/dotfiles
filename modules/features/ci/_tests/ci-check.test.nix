{
  inputs,
  lib,
}:
let
  ciCheck = import ../_interface/check.nix { inherit lib; };
  linuxSystem = "x86_64-linux";
  darwinSystem = "aarch64-darwin";
  additionalSystem = "aarch64-linux";
  validationCheckName = "hestia-job-contract";
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
  mkModuleFixture =
    overrideModule:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        ../../nixpkgs
        ../default.nix
        overrideModule
      ];
      options.features = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
      };
      config = {
        systems = [
          darwinSystem
          linuxSystem
        ];
        perSystem =
          { pkgs, system, ... }:
          let
            targets = ciCheck.targets.both "eval-tests";
          in
          {
            treefmt.flakeCheck = false;
            checks.build = ciCheck.annotate targets (
              pkgs.runCommand "fixture-build-${system}" { } ''touch "$out"''
            );
            dotfiles.ci.buildRouteProducers = [
              {
                owner = "fixture";
                routes.build = targets;
              }
            ];
          };
      };
    };
  validModuleFixture = mkModuleFixture { };
  leafOverrideFixture = mkModuleFixture {
    perSystem =
      {
        lib,
        pkgs,
        system,
        ...
      }:
      lib.optionalAttrs (system == linuxSystem) {
        checks.${validationCheckName} = lib.mkForce (
          pkgs.runCommand "forced-${validationCheckName}" { } ''touch "$out"''
        );
      };
  };
  setOverrideFixture = mkModuleFixture {
    perSystem =
      {
        lib,
        pkgs,
        system,
        ...
      }:
      lib.optionalAttrs (system == linuxSystem) {
        checks = lib.mkForce {
          build = ciCheck.annotate (ciCheck.targets.both "eval-tests") (
            pkgs.runCommand "forced-build" { } ''touch "$out"''
          );
          ${validationCheckName} = pkgs.runCommand "forced-${validationCheckName}" { } ''touch "$out"'';
        };
      };
  };
in
{
  testAnnotationPreservesMetadata = {
    expr = (ciCheck.annotate (ciCheck.targets.both "eval-tests") fakeCheck).meta.description;
    expected = "preserved metadata";
  };

  testEvaluationCompletePreservesMetadata = {
    expr = {
      execution = (ciCheck.evaluationComplete fakeCheck).meta.dotfiles.ci.execution;
      description = (ciCheck.evaluationComplete fakeCheck).meta.description;
    };
    expected = {
      execution = "evaluation-complete";
      description = "preserved metadata";
    };
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
        execution = composition.checks.evaluated.meta.dotfiles.ci.execution;
        description = composition.checks.evaluated.meta.description;
      };
    expected = {
      names = [ "evaluated" ];
      execution = "evaluation-complete";
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
        hasExecution = ((composition.values.evaluated.meta.dotfiles or { }).ci or { }) ? execution;
        hasTargets = ((composition.values.evaluated.meta.dotfiles or { }).hestia or { }) ? targets;
        description = composition.values.evaluated.meta.description;
      };
    expected = {
      hasExecution = false;
      hasTargets = false;
      description = "preserved metadata";
    };
  };

  testBuildProducerKeepsRoutesIndependentFromCheckValues = {
    expr =
      (ciCheck.mkBuildProducer {
        owner = "fixture";
        entries.lazy = ciCheck.buildEntry (ciCheck.targets.linux "eval-tests") (
          throw "build check value was forced"
        );
      }).routes;
    expected.lazy = ciCheck.targets.linux "eval-tests";
  };

  testBuildProducerMaterializesCanonicalMetadata = {
    expr =
      let
        producer = ciCheck.mkBuildProducer {
          owner = "fixture";
          entries.example = ciCheck.buildEntry (ciCheck.targets.both "repo-quality") fakeCheck;
        };
      in
      {
        route = producer.routes.example;
        metadata = producer.checks.example.meta.dotfiles.hestia.targets;
        description = producer.checks.example.meta.description;
      };
    expected = {
      route = ciCheck.targets.both "repo-quality";
      metadata = ciCheck.targets.both "repo-quality";
      description = "preserved metadata";
    };
  };

  testValidLightweightManifest = {
    expr = ciCheck.validateCheckManifest {
      checkNamesBySystem = {
        ${linuxSystem} = [
          "contract"
          "example"
        ];
        ${darwinSystem} = [ "example" ];
        ${additionalSystem} = [ ];
      };
      evaluationCompleteCheckNamesBySystem = {
        ${linuxSystem} = [ "contract" ];
        ${darwinSystem} = [ ];
        ${additionalSystem} = [ ];
      };
      buildRoutesBySystem = {
        ${linuxSystem}.example = ciCheck.targets.both "eval-tests";
        ${darwinSystem}.example = ciCheck.targets.both "eval-tests";
        ${additionalSystem} = { };
      };
    };
    expected = true;
  };

  testValidEvaluationCompleteDefinitionsDoNotForceChecks = {
    expr = ciCheck.validateEvaluationCompleteDefinitions {
      checkDefinitionsBySystem = {
        ${linuxSystem} = [
          {
            file = "owner";
            value.evaluated = throw "evaluation-complete check definition was forced";
          }
        ];
        ${darwinSystem} = [ ];
      };
      evaluationCompleteCheckNamesBySystem = {
        ${linuxSystem} = [ "evaluated" ];
        ${darwinSystem} = [ ];
      };
      expectedFile = "owner";
    };
    expected = true;
  };

  testProductionHestiaWiringAcceptsOwnedDefinition = {
    expr = builtins.attrNames validModuleFixture.lib.hestiaJobs.ci.${linuxSystem};
    expected = [ "build" ];
  };

  testProductionFixtureContainsExpectedEvaluationContract = {
    expr = builtins.hasAttr validationCheckName validModuleFixture.checks.${linuxSystem};
    expected = true;
  };

  testProductionHestiaWiringRejectsForcedLeaf = {
    expr =
      (builtins.tryEval (builtins.attrNames leafOverrideFixture.lib.hestiaJobs.ci.${linuxSystem}))
      .success;
    expected = false;
  };

  testProductionHestiaWiringRejectsForcedSet = {
    expr =
      (builtins.tryEval (builtins.attrNames setOverrideFixture.lib.hestiaJobs.ci.${linuxSystem})).success;
    expected = false;
  };

  testSystemSpecificGroups =
    let
      checkTargets = ciCheck.targets.bySystem {
        darwin = "configurations";
        linux = "repo-quality";
      };
      jobs = ciCheck.mkHestiaJobs {
        checksBySystem = {
          ${linuxSystem}.example = ciCheck.annotate checkTargets fakeCheck;
          ${darwinSystem}.example = ciCheck.annotate checkTargets (
            fakeCheck
            // {
              system = darwinSystem;
            }
          );
        };
        evaluationCompleteCheckNamesBySystem = {
          ${linuxSystem} = [ ];
          ${darwinSystem} = [ ];
        };
        routesBySystem = {
          ${linuxSystem}.example = checkTargets;
          ${darwinSystem}.example = checkTargets;
        };
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
        checksBySystem = {
          ${linuxSystem} = {
            both = ciCheck.annotate bothTargets (fakeFor "both-linux" linuxSystem);
            linuxOnly = ciCheck.annotate linuxTargets (fakeFor "linux-only" linuxSystem);
          };
          ${darwinSystem} = {
            both = ciCheck.annotate bothTargets (fakeFor "both-darwin" darwinSystem);
            darwinOnly = ciCheck.annotate darwinTargets (fakeFor "darwin-only" darwinSystem);
          };
        };
        evaluationCompleteCheckNamesBySystem = {
          ${linuxSystem} = [ ];
          ${darwinSystem} = [ ];
        };
        routesBySystem = {
          ${linuxSystem} = {
            both = bothTargets;
            linuxOnly = linuxTargets;
          };
          ${darwinSystem} = {
            both = bothTargets;
            darwinOnly = darwinTargets;
          };
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
        checksBySystem = {
          ${linuxSystem}.example = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
          ${darwinSystem} = throw "sibling system was forced";
        };
        evaluationCompleteCheckNamesBySystem = {
          ${linuxSystem} = [ ];
          ${darwinSystem} = throw "sibling evaluation-complete names were forced";
        };
        routesBySystem = {
          ${linuxSystem}.example = ciCheck.targets.linux "eval-tests";
          ${darwinSystem} = throw "sibling routes were forced";
        };
      }).${linuxSystem}
    );
    expected = [ "example" ];
  };

  testHestiaJobIndexDoesNotForceEvaluationCompleteChecks = {
    expr = builtins.attrNames (
      (ciCheck.mkHestiaJobs {
        checksBySystem = {
          ${linuxSystem} = {
            build = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
            evaluated = throw "evaluation-complete check was forced while indexing jobs";
          };
          ${darwinSystem} = { };
        };
        evaluationCompleteCheckNamesBySystem = {
          ${linuxSystem} = [ "evaluated" ];
          ${darwinSystem} = [ ];
        };
        routesBySystem = {
          ${linuxSystem}.build = ciCheck.targets.linux "eval-tests";
          ${darwinSystem} = { };
        };
      }).${linuxSystem}
    );
    expected = [ "build" ];
  };

  testHestiaJobIndexDoesNotForceBuildChecks = {
    expr = builtins.attrNames (
      (ciCheck.mkHestiaJobs {
        checksBySystem = {
          ${linuxSystem}.build = throw "build check was forced while indexing jobs";
          ${darwinSystem} = { };
        };
        evaluationCompleteCheckNamesBySystem = {
          ${linuxSystem} = [ ];
          ${darwinSystem} = [ ];
        };
        routesBySystem = {
          ${linuxSystem}.build = ciCheck.targets.linux "eval-tests";
          ${darwinSystem} = { };
        };
      }).${linuxSystem}
    );
    expected = [ "build" ];
  };

  testHestiaJobsDoNotForceEvaluationCompleteChecks = {
    expr =
      let
        jobs = ciCheck.mkHestiaJobs {
          checksBySystem = {
            ${linuxSystem} = {
              build = ciCheck.annotate (ciCheck.targets.linux "eval-tests") fakeCheck;
              evaluated = throw "evaluation-complete check was forced by a build job";
            };
            ${darwinSystem} = { };
          };
          evaluationCompleteCheckNamesBySystem = {
            ${linuxSystem} = [ "evaluated" ];
            ${darwinSystem} = [ ];
          };
          routesBySystem = {
            ${linuxSystem}.build = ciCheck.targets.linux "eval-tests";
            ${darwinSystem} = { };
          };
        };
      in
      jobs.${linuxSystem}.build.meta.description;
    expected = "preserved metadata";
  };

}
