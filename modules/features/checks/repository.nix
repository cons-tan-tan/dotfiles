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
    "darwin-system-hcom-enabled"
    "home-linux"
    "home-linux-hcom-enabled"
    "home-wsl"
    "home-wsl-hcom-enabled"
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
