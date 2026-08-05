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
  evaluationCompleteCheckNamesBySystem = lib.genAttrs config.systems (
    system: withSystem system ({ config, ... }: config.dotfiles.ci.evaluationCompleteCheckNames)
  );
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
    # metadataから導出すると除外前にcheck値を強制するため、ownerが名前indexも
    # 寄与する。通常flake評価のcontractがmetadataとの一致を検証する。
    options.dotfiles.ci.evaluationCompleteCheckNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Checks whose assertions finish before derivation build";
    };
  };

  config = {
    perSystem =
      {
        pkgs,
        system,
        ...
      }:
      {
        treefmt.settings.formatter.nixf-diagnose.excludes = [
          "modules/features/ci/_packages/gha-lint/bun.nix"
        ];

        dotfiles.ci.evaluationCompleteCheckNames = lib.optionals (system == "x86_64-linux") [
          validationCheckName
        ];

        checks = lib.optionalAttrs (system == "x86_64-linux") {
          ${validationCheckName} = ciCheck.evaluationComplete (
            builtins.seq validation (pkgs.runCommand validationCheckName { } ''touch "$out"'')
          );
        };
      };

    features.ci-tools = {
      name = "feature/ci/tools";
      homeManager =
        { pkgs, ... }:
        {
          home.packages = [
            pkgs.pinact
            pkgs.zizmor
            pkgs.dotfilesPackages.gha-lint
          ];
        };
    };

    flake.hydraJobs.ci = ciCheck.mkHestiaJobs buildChecksBySystem;
  };
}
