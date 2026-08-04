{
  config,
  den,
  inputs,
  lib,
  ...
}:
let
  username = "constantan";
  ciCheck = import ../../../nix/lib/ci-check.nix { inherit lib; };
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
  den.aspects.repository-checks.checks =
    { pkgs, system, ... }:
    let
      baseChecks = lib.optionalAttrs (system == "x86_64-linux") {
        den-capability-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/den-capabilities.nix {
            inherit inputs lib pkgs;
          }
        );
        den-schema-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/den-capabilities.nix {
            inherit inputs lib pkgs;
            checkName = "den-schema-tests";
            fixturePath = ../../_tests/den-schema.nix;
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
          import ../../../nix/checks/den-capabilities.nix {
            inherit inputs lib pkgs;
            checkName = "agent-den-dataflow-tests";
            fixturePath = ../agents/_tests/dataflow.nix;
            fixtureRoot = ../../..;
          }
        );
        cli-tools-dataflow-tests = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../../../nix/checks/den-capabilities.nix {
            inherit inputs lib pkgs;
            checkName = "cli-tools-dataflow-tests";
            fixturePath = ../packages/_tests/dataflow.nix;
            fixtureRoot = ../../..;
          }
        );
        home-feature-contract = ciCheck.annotate (ciCheck.targets.linux "eval-tests") (
          import ../_tests/home-feature-contract.nix {
            inherit inputs lib pkgs;
            flake = config.flake;
          }
        );
        platform-feature-contract = ciCheck.annotate (ciCheck.targets.linux "configurations") (
          import ../platform/_tests/contract.nix {
            inherit
              lib
              pkgs
              username
              ;
            flake = config.flake;
          }
        );
        windows-class-contract =
          let
            outputContract = import ../windows/_tests/class-contract.nix {
              inherit
                inputs
                lib
                pkgs
                username
                ;
              flake = config.flake;
            };
            dataflowContract = import ../../../nix/checks/den-capabilities.nix {
              inherit inputs lib pkgs;
              checkName = "windows-class-dataflow-tests";
              fixturePath = ../windows/_tests/dataflow.nix;
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
    baseChecks // testChecks;

  den.schema.flake-parts.includes = [ den.aspects.repository-checks ];
}
