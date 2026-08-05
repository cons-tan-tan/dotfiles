{
  config,
  lib,
  ...
}:
let
  ciCheck = import ./_interface/check.nix { inherit lib; };
in
{
  perSystem.treefmt.settings.formatter.nixf-diagnose.excludes = [
    "modules/features/ci/_packages/gha-lint/bun.nix"
  ];

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

  flake.hydraJobs.ci = ciCheck.mkHestiaJobs {
    aarch64-darwin = config.flake.checks.aarch64-darwin;
    x86_64-linux = config.flake.checks.x86_64-linux;
  };
}
