{
  config,
  flake-parts-lib,
  lib,
  withSystem,
  ...
}:
let
  ciCheck = import ./_interface/check.nix { inherit lib; };
  validationCheckName = "hestia-job-contract";
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
  buildChecksBySystem = lib.genAttrs hestiaSystems (
    system:
    ciCheck.selectBuildChecks {
      checks = checksBySystem.${system};
      evaluationCompleteCheckNames = evaluationCompleteCheckNamesBySystem.${system};
      inherit system;
    }
  );
  validation = builtins.all (result: result) [
    (ciCheck.validateEvaluationCompleteChecks {
      inherit checksBySystem evaluationCompleteCheckNamesBySystem;
      ignoredCheckNamesBySystem.x86_64-linux = [ validationCheckName ];
    })
    (ciCheck.validateHestiaJobs buildChecksBySystem)
  ];
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    # check値のmetadataを読むとeval suiteを強制し得る。producerは名前と値を
    # attrset境界で分離し、attrNamesだけから安全に除外indexを構成する。
    options.dotfiles.ci.evaluationCompleteCheckProducers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            owner = lib.mkOption { type = lib.types.nonEmptyStr; };
            checks = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.raw; };
          };
        }
      );
      default = [ ];
      internal = true;
      description = "Lazily indexed checks whose assertions finish before derivation build";
    };
  };

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

        checks =
          (ciCheck.composeEvaluationCompleteProducers config.dotfiles.ci.evaluationCompleteCheckProducers)
          .checks;
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

    flake.hydraJobs.ci = ciCheck.mkHestiaJobs buildChecksBySystem;
  };
}
