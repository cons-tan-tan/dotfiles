{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  ciCheck = import ../../../nix/lib/ci-check.nix { inherit lib; };
  configurationTargets = import ../../entities/_lib/configuration-targets.nix { inherit lib; };
  composeUniqueChecks = import ../../../nix/tests/compose.nix { inherit lib; };
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
    "nixos-wsl-contract"
    "nixos-wsl-system"
    "nixos-wsl-tarball-builder"
    "treefmt"
  ];
in
{
  flake-file.inputs.rustsec-advisory-db = {
    url = "github:RustSec/advisory-db";
    flake = false;
  };

  den.aspects.repository-checks.checks =
    { pkgs, system, ... }:
    let
      entityContext = configurationTargets { inherit den system; };
      username = entityContext.username;
      entityContexts = {
        darwin = configurationTargets {
          inherit den;
          system = "aarch64-darwin";
        };
        linuxX86 = configurationTargets {
          inherit den;
          system = "x86_64-linux";
        };
        linuxAarch64 = configurationTargets {
          inherit den;
          system = "aarch64-linux";
        };
      };
      baseChecks = lib.optionalAttrs (system == "x86_64-linux") {
        den-capability-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/tests/eval/den-suite-harness.nix {
            inherit inputs lib pkgs;
            fixtureRoot = ../../..;
          }
        );
        den-schema-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/tests/eval/den-suite-harness.nix {
            inherit inputs lib pkgs;
            checkName = "den-schema-tests";
            fixturePath = ../../_tests/den-schema.suite.nix;
            fixtureRoot = ../../..;
            schemaModule = ../../schema/entities.nix;
          }
        );
        den-entity-topology-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/den-entity-topology.nix {
            inherit
              den
              inputs
              lib
              pkgs
              ;
            flake = config.flake;
          }
        );
        den-unfree-capability-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/den-unfree-capability.nix {
            inherit inputs lib pkgs;
          }
        );
        agent-den-dataflow-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/tests/eval/den-suite-harness.nix {
            inherit inputs lib pkgs;
            checkName = "agent-den-dataflow-tests";
            fixturePath = ../agents/_tests/dataflow.suite.nix;
            fixtureRoot = ../../..;
          }
        );
        cli-tools-dataflow-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/tests/eval/den-suite-harness.nix {
            inherit inputs lib pkgs;
            checkName = "cli-tools-dataflow-tests";
            fixturePath = ../packages/_tests/dataflow.suite.nix;
            fixtureRoot = ../../..;
          }
        );
        home-feature-contract = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/home-feature-contract.nix {
            inherit
              entityContexts
              inputs
              lib
              pkgs
              ;
            flake = config.flake;
          }
        );
        platform-feature-contract = ciCheck.annotate (ciCheck.targets.linux "configurations") (
          import ../../../nix/checks/platform-feature-contract.nix {
            inherit
              entityContexts
              lib
              pkgs
              ;
            flake = config.flake;
          }
        );
        windows-class-contract =
          let
            outputContract = import ../../../nix/checks/windows-class-contract.nix {
              inherit
                entityContexts
                inputs
                lib
                pkgs
                ;
              flake = config.flake;
            };
            dataflowContract = import ../../../nix/tests/eval/den-suite-harness.nix {
              inherit inputs lib pkgs;
              checkName = "windows-class-dataflow-tests";
              fixturePath = ../windows/_tests/dataflow.suite.nix;
              fixtureRoot = ../../..;
            };
          in
          ciCheck.annotate (ciCheck.targets.linux "configurations") (
            pkgs.linkFarm "windows-class-contract" [
              {
                name = "outputs";
                path = outputContract;
              }
              {
                name = "dataflow";
                path = dataflowContract;
              }
            ]
          );
        flake-public-api-contract = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/flake-public-api-contract.nix {
            inherit lib pkgs;
            systems = config.systems;
            inherit (config.flake)
              apps
              checks
              darwinConfigurations
              devShells
              formatter
              homeConfigurations
              nixosConfigurations
              packages
              ;
            rootPackagesPresent = config.flake ? packages;
          }
        );
      };
      testChecks = import ../../../nix/tests {
        inherit
          ciCheck
          den
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
        reservedCheckNames = externallyOwnedCheckNames ++ builtins.attrNames baseChecks;
      };
    in
    composeUniqueChecks {
      producers = [
        {
          owner = "repository base checks";
          checks = baseChecks;
        }
        {
          owner = "repository test checks";
          checks = testChecks;
        }
      ];
      reservedCheckNames = externallyOwnedCheckNames;
    };

  den.schema.flake-parts.includes = [ den.aspects.repository-checks ];
}
