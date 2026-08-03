{ config, lib, ... }:
let
  ciCheck = import ../../nix/lib/ci-check.nix { inherit lib; };
in
{
  flake.hydraJobs.ci = ciCheck.mkHestiaJobs {
    aarch64-darwin = config.flake.checks.aarch64-darwin;
    x86_64-linux = config.flake.checks.x86_64-linux;
  };
}
