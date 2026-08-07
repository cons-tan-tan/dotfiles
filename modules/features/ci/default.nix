{
  config,
  lib,
  withSystem,
  ...
}:
let
  ciCheck = import ./_interface/check.nix { inherit lib; };
  validationCheckName = "hestia-job-contract";
  # Hestia must omit these checks without forcing their values. A dedicated
  # definition source lets the contract reject later overrides by name alone.
  evaluationCompleteDefinitionOwner = "feature/ci evaluation-complete check materializer";
  hestiaSystems = [
    "aarch64-darwin"
    "x86_64-linux"
  ];
  checksBySystem = lib.genAttrs config.systems (
    system: withSystem system ({ config, ... }: config.checks)
  );
  evaluationCompleteCheckProducersBySystem = lib.genAttrs config.systems (
    system: withSystem system ({ config, ... }: config.dotfiles.ci.evaluationCompleteCheckProducers)
  );
  evaluationCompleteCompositionBySystem = lib.mapAttrs (
    _: producers: ciCheck.composeEvaluationCompleteProducers producers
  ) evaluationCompleteCheckProducersBySystem;
  evaluationCompleteCheckNamesBySystem = lib.mapAttrs (
    _: composition: composition.checkNames
  ) evaluationCompleteCompositionBySystem;
  checkNamesBySystem = lib.mapAttrs (_: checks: builtins.attrNames checks) checksBySystem;
  checkDefinitionsBySystem = lib.genAttrs config.systems (
    system: withSystem system ({ options, ... }: options.checks.definitionsWithLocations)
  );
  buildRouteProducersBySystem = lib.genAttrs config.systems (
    system: withSystem system ({ config, ... }: config.dotfiles.ci.buildRouteProducers)
  );
  buildRoutesBySystem = lib.mapAttrs (
    _: producers: ciCheck.composeRouteProducers producers
  ) buildRouteProducersBySystem;
  hestiaChecksBySystem = lib.genAttrs hestiaSystems (system: checksBySystem.${system});
  hestiaEvaluationCompleteCheckNamesBySystem = lib.genAttrs hestiaSystems (
    system: evaluationCompleteCheckNamesBySystem.${system}
  );
  hestiaRoutesBySystem = lib.genAttrs hestiaSystems (system: buildRoutesBySystem.${system});
  validation =
    builtins.seq
      (ciCheck.validateEvaluationCompleteDefinitions {
        inherit checkDefinitionsBySystem evaluationCompleteCheckNamesBySystem;
        expectedFile = evaluationCompleteDefinitionOwner;
      })
      (
        ciCheck.validateCheckManifest {
          inherit buildRoutesBySystem checkNamesBySystem evaluationCompleteCheckNamesBySystem;
        }
      );
in
{
  imports = [ ./_interface/options.nix ];

  config = {
    perSystem =
      {
        config,
        pkgs,
        system,
        ...
      }:
      {
        treefmt.settings.formatter.nixf-diagnose.excludes = [
          "modules/features/ci/_packages/gha-lint/bun.nix"
        ];

        dotfiles.ci.evaluationCompleteCheckProducers = lib.optionals (system == "x86_64-linux") [
          {
            owner = "CI validation";
            checks.${validationCheckName} = builtins.seq validation (
              pkgs.runCommand validationCheckName { } ''touch "$out"''
            );
          }
        ];

        checks = lib.mkDefinition {
          file = evaluationCompleteDefinitionOwner;
          value =
            (ciCheck.composeEvaluationCompleteProducers config.dotfiles.ci.evaluationCompleteCheckProducers)
            .checks;
        };
      };

    features.ci-tools = {
      name = "feature/ci/tools";
      homeManager =
        { pkgs, ... }:
        {
          home.packages = [
            pkgs.pinact
            pkgs.dotfilesPackages.gha-lint
            pkgs.dotfilesPackages.zizmor
          ];
        };
    };

    flake.lib.hestiaJobs.ci = builtins.seq validation (
      ciCheck.mkHestiaJobs {
        checksBySystem = hestiaChecksBySystem;
        evaluationCompleteCheckNamesBySystem = hestiaEvaluationCompleteCheckNamesBySystem;
        routesBySystem = hestiaRoutesBySystem;
      }
    );
  };
}
