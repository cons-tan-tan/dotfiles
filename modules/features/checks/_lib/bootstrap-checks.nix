{
  ciCheck,
  lib,
  pkgs,
  repoRoot,
  testContext,
  testDiscovery,
}:
let
  paths = [
    ../_tests/test-discovery.test.nix
    ../_tests/dendritic-test-discovery.test.nix
    ../_tests/dendritic-module-boundary.test.nix
  ];

  harness = import ./eval/harness.nix {
    inherit
      ciCheck
      lib
      pkgs
      repoRoot
      testContext
      testDiscovery
      ;
  };
  positiveChecks = harness.positiveChecks paths;
  discoveryCheckName = testDiscovery.checkName ../_tests/test-discovery.test.nix;
  diagnosticContract = harness.isolatedFailureCheck {
    name = "test-discovery-diagnostics";
    path = ./eval/test-discovery-diagnostics.failure.fixture.nix;
  };
  checks = lib.mapAttrs (
    name: check:
    if name == discoveryCheckName then
      ciCheck.annotate (ciCheck.targets.both "eval-tests") (
        pkgs.linkFarm discoveryCheckName [
          {
            name = "positive";
            path = check;
          }
          {
            name = "diagnostics";
            path = diagnosticContract;
          }
        ]
      )
    else
      check
  ) positiveChecks;
in
{
  inherit paths;
  names = map testDiscovery.checkName paths;
  inherit checks;
}
