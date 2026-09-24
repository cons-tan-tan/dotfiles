{
  config,
  inputs,
  lib,
  ...
}:
let
  ciCheck = import ../ci/_interface/check.nix { inherit lib; };
  composeUniqueChecks = import ./_lib/compose.nix { inherit ciCheck lib; };
  modulesRoot = ../..;
  testDiscovery = import ./_lib/test-discovery.nix { inherit lib; };
  evalInventory = import ./_interface/eval/inventory.nix {
    inherit modulesRoot testDiscovery;
  };
  externallyOwnedCheckNames = [
    "app-scripts"
    "check-flake-file"
    "claude-userprofile-contract"
    "configuration-ownership-contract"
    "darwin-nh-cleanup-contract"
    "darwin-system"
    "home-linux"
    "home-darwin-hcom-profile"
    "home-linux-hcom-profile"
    "home-wsl"
    "home-wsl-hcom-profile"
    "hestia-job-contract"
    "nixos-wsl-contract"
    "nixos-wsl-system"
    "nixos-wsl-tarball-builder"
    "treefmt"
  ];
  repositoryChecks =
    { pkgs, system }:
    let
      entityContext = config.dotfiles.targets.${system};
      username = entityContext.username;
      entityContexts = {
        darwin = config.dotfiles.targets."aarch64-darwin";
        linuxX86 = config.dotfiles.targets."x86_64-linux";
        linuxAarch64 = config.dotfiles.targets."aarch64-linux";
      };
      moduleSuiteProducer =
        if system == "x86_64-linux" then
          (import ./_lib/eval/module-suite-harness.nix {
            inherit
              ciCheck
              inputs
              lib
              pkgs
              ;
            repoRoot = ../../..;
          }).producer
            evalInventory.moduleSuiteFiles
        else
          {
            buildEntries = { };
            evaluationCompleteChecks = { };
          };
      repositoryEvaluationCompleteChecks = lib.optionalAttrs (system == "x86_64-linux") {
        ci-required-gates-contract = import ../ci/_tests/required-gates-contract.nix {
          checks = config.flake.checks;
          inherit lib pkgs;
        };
        home-feature-contract = import ./_interface/home-contract.nix {
          inherit
            entityContexts
            inputs
            lib
            pkgs
            ;
          flake = config.flake;
          repoRoot = ../../..;
        };
        platform-feature-contract = import ../platform/_tests/feature-contract.nix {
          inherit
            entityContexts
            lib
            pkgs
            ;
          featuresRoot = ../.;
          flake = config.flake;
        };
        flake-public-api-contract = import ../../flake/_tests/public-api-contract.nix {
          inherit lib pkgs;
          systems = config.systems;
          inherit (config.flake)
            apps
            darwinConfigurations
            devShells
            formatter
            homeConfigurations
            nixosConfigurations
            packages
            ;
          rootPackagesPresent = config.flake ? packages;
          rootHestiaCiPresent =
            config.flake ? lib && config.flake.lib ? hestiaJobs && config.flake.lib.hestiaJobs ? ci;
          rootHydraCiPresent = config.flake ? hydraJobs && config.flake.hydraJobs ? ci;
        };
      };
      repositoryBuildEntries = lib.optionalAttrs (system == "x86_64-linux") {
        windows-class-contract = ciCheck.buildEntry (ciCheck.targets.linux "configurations") (
          import ../windows/_tests/class-contract.nix {
            inherit
              entityContexts
              lib
              pkgs
              ;
            flake = config.flake;
          }
        );
      };
      repositoryOwnedNames =
        builtins.attrNames repositoryBuildEntries
        ++ builtins.attrNames moduleSuiteProducer.buildEntries
        ++ builtins.attrNames repositoryEvaluationCompleteChecks
        ++ builtins.attrNames moduleSuiteProducer.evaluationCompleteChecks;
      testCheckSet = import ./_interface/repository-tests.nix {
        configurationTargets = config.dotfiles.targets;
        inherit
          ciCheck
          inputs
          lib
          pkgs
          username
          ;
        advisoryDb = inputs.rustsec-advisory-db;
        advisoryDbLastModified = inputs.rustsec-advisory-db.lastModified;
        flake = config.flake;
        homeManager = inputs.home-manager;
        llmAgents = inputs.llm-agents;
        publicApps = config.flake.apps.${system};
        repoRoot = ../../..;
        reservedCheckNames = externallyOwnedCheckNames ++ repositoryOwnedNames;
      };
      evaluationCompleteComposition = ciCheck.composeEvaluationCompleteProducers [
        {
          owner = "repository base checks";
          checks = repositoryEvaluationCompleteChecks;
        }
        {
          owner = "Module suites";
          checks = moduleSuiteProducer.evaluationCompleteChecks;
        }
        {
          owner = "repository test checks";
          checks = testCheckSet.evaluationCompleteChecks;
        }
      ];
      buildComposition = composeUniqueChecks {
        producers = [
          (ciCheck.mkBuildProducer {
            owner = "repository base checks";
            entries = repositoryBuildEntries;
          })
          (ciCheck.mkBuildProducer {
            owner = "Module suites";
            entries = moduleSuiteProducer.buildEntries;
          })
          {
            owner = "repository test checks";
            checks = testCheckSet.buildChecks;
            routes = testCheckSet.buildRoutes;
          }
        ];
        reservedCheckNames = externallyOwnedCheckNames ++ evaluationCompleteComposition.checkNames;
      };
    in
    {
      buildChecks = buildComposition.checks;
      buildRoutes = buildComposition.routes;
      evaluationCompleteChecks = evaluationCompleteComposition.values;
    };
in
{
  imports = [ ../ci/_interface/options.nix ];

  flake-file.inputs.rustsec-advisory-db = {
    url = "github:RustSec/advisory-db";
    flake = false;
  };

  perSystem =
    { pkgs, system, ... }:
    let
      checks = repositoryChecks { inherit pkgs system; };
    in
    {
      checks = checks.buildChecks;
      dotfiles.ci = {
        evaluationCompleteCheckProducers = [
          {
            owner = "repository checks";
            checks = checks.evaluationCompleteChecks;
          }
        ];
        buildRouteProducers = [
          {
            owner = "repository checks";
            routes = checks.buildRoutes;
          }
        ];
      };
    };
}
